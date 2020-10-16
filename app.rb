require "net/http"
require "json"

require 'sinatra'
require "sinatra/reloader"
require "sinatra/json"

require 'rom'
require 'rom-repository'
require 'rom/transformer'

require 'rubyfocus'
require "rdiscount"

require 'notion_rb'
require 'dotenv/load'
require 'pry'

NOTION_URL = ENV['NOTION_URL']
NOTION_MOOD_BOARD = ENV['NOTION_MOOD_BOARD']
NOTION_ID = ENV['NOTION_ID']
WEEKDAY_TAGS = {
  "Fri" => "F",
  "Thu" => "Th",
  "Wed" => "W",
  "Mon" => "M",
  "Tue" => "Tu",
  "Sat" => "",
}
POMODORO_TAGS = {
  "eNLnAheg2ZH" => 1,
  "bTydq4wXcv-" => 2,
  "cnGz5rrnQdN" => 3,
  "mteIDiVe00P" => 4,
  "d2RbzksTDsq" => 5
}

class TaskMapper < ROM::Transformer
  relation :tasks, as: :task_mapper

  map do
    deep_stringify_keys
  end
end
rom = ROM.container(:sql, 'sqlite://board.db') do |config|
  config.relation(:tasks) do
    schema(infer: true)
    auto_struct true
  end
  config.register_mapper(TaskMapper)
end

class TaskRepo < ROM::Repository[:tasks]
  def by_omni_id(omni_id)
    tasks.where(omni_id: omni_id).first
  end
  def by_omni_ids(omni_ids)
    tasks.where(omni_id: omni_ids)
  end
end
task_repo = TaskRepo.new(rom)

class NullItem
  def id
    ""
  end
  def title
    ""
  end
end

class Criteria
  def initialize(klass)
    @klass = klass
  end
  def criteria
    @criteria ||= {:conditions => {}}
  end

  def each(&block)
    @klass.collection.select(
      criteria[:conditions]
    ).each(&block)
  end
end
# ! methods change the @tasks and are for method chaining and return self
class Tasks
  def initialize(tasks)
    @tasks = tasks
  end
  def available
    @tasks.select { |t| not t.completed }
  end
  def available!
    @tasks = available
    self
  end
  def by_tag_title(tag)
    @tasks.select { |t| t.includes_tag_title?(tag)}
  end
  def by_tag_title!(tag)
    @tasks = by_tag_title(tag)
    self
  end
  def pomodoros
    @tasks.reduce(0) do |sum, task|
      POMODORO_TAGS.reduce(sum) do | s, (id, value) |
        if task.tags.any? { |t|  t.id == id }
          s += value
        end
        s
      end
    end
  end
  def tasks
    @tasks
  end
  def size
    @tasks.size
  end
  def each(&block)
    @tasks.each(&block)
  end
  def to_json
    self.to_h.to_json
  end
end
Task = Struct.new(:id, :title, :project, :tag, :tags, :flagged, :completed) do
  def includes_tag_title?(tag)
    tags.any? { |t| t.title == tag}
  end
  def to_json(opt={})
    self.to_h.to_json
  end
end
Project = Struct.new(:id, :title, :tag, :tasks) do
  def to_json(opt={})
    h = self.to_h
    h.delete(:tasks)
    h.to_json
  end
end
Context = Struct.new(:id, :title) do
  def to_json(opt={})
    self.to_h.to_json
  end
end
Stat = Struct.new(:title, :text)
Mood = Struct.new(:title, :omni_id, :icon, :color) do
  def slug
    title.downcase
  end
end

class Moods
  def initialize
    @moods = [
      Mood.new("Creative", "jD1WSrQuMCl", "", ""),
      Mood.new("Thoughtful", "nkCRtrShFCL", "", ""),
      Mood.new("Excited", "hyUS2LTaoAu", "", ""),
      Mood.new("Bored", "pwaIB7zoloH", "", ""),
      Mood.new("Critical", "f0zFjP9USZT", "", ""),
      Mood.new("Curious", "hATq-ppnCQg", "", ""),
      Mood.new("Reflective", "a10MJQsAoWR", "", ""),
      Mood.new("Overwhelmed", "l73IXIUaFLz", "", ""),
      Mood.new("Sluggish", "lDVqP_51otn", "", "")
    ]
  end

  def moods
    @moods
  end

  def mood_by_slug(slug)
    @moods.find { |m| m.slug == slug}
  end
end
class Omni

  def initialize
    f = Rubyfocus::LocalFetcher.new
    @omni = Rubyfocus::Document.new(f)
    @omni.update
    @projects = {}
    @contexts = {}
  end

  def update
    @omni.update
  end

  def this_week
    puts "This week id: #{this_week_id}"
    get_tasks_by_tag_id(this_week_id)
  end

  def today
    today_tag = get_context_id_by_name(WEEKDAY_TAGS[Time.now.strftime("%a")])
    get_tasks_by_tag_ids([this_week_id, today_tag])
  end

  def this_week_id
    get_context_id_by_name("This week")
  end

  def get_task(task_id)
    enhance_task(@omni.tasks.find(task_id))
  end

  def find_project(project_id, add_tasks = false)
    p = @omni.projects.find(project_id)
    project = Project.new(p.id, p.name, p.context_id)
    tasks = p.tasks.map { |task| enhance_task(task, project) } if add_tasks
    project.tasks = tasks
    @projects[p.id] = project
    project
  end

  def get_project_and_tasks(project_id)
    find_project(project_id, true)
  end
  def get_project(project_id)
    @projects[project_id] || find_project(project_id)
  end

  def find_context(context_id)
    p = @omni.contexts.find(context_id)
    context = Context.new(p.id, p.name)
    @contexts[p.id] = context
    context
  end

  def get_context_id_by_name(name)
    c = @omni.contexts.find(name: name)
    c ? c.id : ""
  end

  def get_context(context_id)
    @contexts[context_id] || find_context(context_id)
  end

  def get_tasks_for_context_id(id)
    @omni.contexts_tasks.select(context_id: id).map(&:task).reject(&:nil?)
  end
  def get_tasks_by_tag_id(id)
    puts "Context id: #{id}"
    update
    Tasks.new(enhance_tasks(get_tasks_for_context_id(id)))
  end

  def get_tasks_by_tag_ids(ids)
    update
    tasks = get_tasks_for_context_id(ids[0])
    t = tasks.select { |t|
      context_ids = t.contexts.map { |c| c.id }
      ids.all? { |c| context_ids.include?(c)  }
    } if tasks
    Tasks.new(enhance_tasks(t))
  end

  def enhance_task(task, project = nil)
    project = task.container_id ? get_project(task.container_id) : NullItem.new unless project
    tag = get_context(task.context_id)
    tags = task.contexts.map { |c| get_context(c.id) }
    completed = task.completed?
    Task.new(task.id, task.name, project, tag, tags, task.flagged, completed)
  end
  def enhance_tasks(tasks)
    tasks.map { |task| enhance_task(task) }
  end
end

omni = Omni.new
moods = Moods.new
enable :sessions

get '/' do
  @tasks = omni.today.available!
  @important = Tasks.new(@tasks.tasks).by_tag_title!("Important")
  @stats = [Stat.new("# tasks", @tasks.size), Stat.new("Pomodoros", @tasks.pomodoros)]
  haml :index
end

get '/this-week' do
  @tasks = omni.this_week.available!
  @important = Tasks.new(@tasks.tasks).by_tag_title!("Important")
  @not_important = Tasks.new(@tasks.tasks).by_tag_title!("Not Important")
  @stats = [Stat.new("# tasks", @tasks.size), Stat.new("Pomodoros", @tasks.pomodoros)]
  haml :overview
end

get '/this-week/today' do
  @tasks = omni.today.available!
  @important = Tasks.new(@tasks.tasks).by_tag_title!("Important")
  @stats = [Stat.new("# tasks", @tasks.size), Stat.new("Pomodoros", @tasks.pomodoros)]
  haml :overview
end

get '/this-week/:weekday' do |weekday|
  @tasks = omni.this_week.by_tag_title!(weekday).available!
  @important = Tasks.new(@tasks.tasks).by_tag_title!("Important")
  @stats = [Stat.new("# tasks", @tasks.size), Stat.new("Pomodoros", @tasks.pomodoros)]
  haml :overview
end


get '/new' do
  @moods = moods.moods
  haml :moods
end

get '/new/mood/:slug' do |n|
  Thread.new {
    response = Net::HTTP.post(URI("#{NOTION_URL}/mood/#{n}"),
                              { }.to_json,
                              "Content-Type" => "application/json"
                             )
    body = JSON.parse(response.body)
    session[:notion_mood_id] = body[:notion_id]
  }
  redirect to("/moods/#{n}")
end

get '/moods/:slug' do |n|
  @mood = moods.mood_by_slug(n)
  puts "Mood: #{@mood} id: #{@mood.omni_id}"
  @tasks = omni.get_tasks_by_tag_id(@mood.omni_id).available!
  haml :mood
end

get '/today' do
  @tasks = omni.today.available!
  haml :tasks
end

get '/project/:id' do |task_id|
  @project = omni.get_project_and_tasks(task_id)
  ids = @project.tasks.map(&:id)
  @tasks = task_repo.by_omni_ids(ids).map_with(:task_mapper).to_a
  haml :project
end
get '/tasks/:id' do |task_id|
  @task = omni.get_task(task_id)
  @hillchart_task = task_repo.by_omni_id(task_id) || task_repo.tasks.changeset(:create, title: @task.title, omni_id: task_id).commit
  haml :task
end
get '/tasks/:id/new' do |task_id|
  redirect to("/tasks/#{task_id}/progress")
end
get '/tasks/:id/progress' do |task_id|
  task = omni.get_task(task_id)
  hillchart_task = task_repo.by_omni_id(task_id) || task_repo.tasks.changeset(:create, title: task.title, omni_id: task_id).commit
  haml :hillchart, locals: { task: hillchart_task }
end
post '/tasks/:id/progress' do |task_id|
  response = ""
  request.body.rewind  # in case someone already read it
  data = JSON.parse request.body.read
  update_task = task_repo.tasks.by_pk(task_id).command(:update)
  response = update_task.call(x: data["x"], y: data["y"]) if update_task
  json success: true, task_id: task_id, response: response
end
