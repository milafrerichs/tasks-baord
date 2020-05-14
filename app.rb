require 'sinatra'
require 'rubyfocus'
require 'notion_rb'
require 'dotenv/load'
require 'pry'

NOTION_MOOD_BOARD = ENV['NOTION_MOOD_BOARD']
NOTION_ID = ENV['NOTION_ID']

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

  def today
    puts "This week id: #{this_week_id}"
    enhance_tasks(@omni.tasks.select(context_id: this_week_id))
  end

  def this_week_id
    @omni.contexts.find(name: "This week").id
  end

  def find_project(project_id)
    p = @omni.projects.find(project_id)
    project = Project.new(p.name, p.context_id)
    @projects[p.id] = project
    project
  end

  def get_project(project_id)
    @projects[project_id] || find_project(project_id)
  end

  def find_context(context_id)
    p = @omni.contexts.find(context_id)
    context = Context.new(p.name)
    @contexts[p.id] = context
    context
  end

  def get_context(context_id)
    @contexts[context_id] || find_context(context_id)
  end

  def get_tasks_by_tag_id(id)
    puts "Context id: #{id}"
    update
    enhance_tasks(@omni.tasks.select(context_id: id))
  end

  def enhance_tasks(tasks)
    tasks.map do |task|
      project = get_project(task.container_id)
      tag = get_context(task.context_id)
      Task.new(task.name, project, tag, task.flagged)
    end
  end
end

Task = Struct.new(:title, :project, :tag, :flagged, :completed) do
end
Project = Struct.new(:title, :tag)
Context = Struct.new(:title)
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

omni = Omni.new
moods = Moods.new
enable :sessions

get '/' do
  haml :index
end

get '/this-week' do
  @tasks = omni.today
  haml :tasks
end

get '/new' do
  @moods = moods.moods
  haml :moods
end

get '/new/mood/:slug' do |n|
  #id = notion.record_mood(n)
  #session[:notion_mood_id] = id
  redirect to("/moods/#{n}")
end

get '/moods/:slug' do |n|
  mood = moods.mood_by_slug(n)
  puts "Mood: #{mood} id: #{mood.omni_id}"
  @tasks = omni.get_tasks_by_tag_id(mood.omni_id)
  haml :tasks
end

get '/today' do
  @tasks = omni.today
  haml :tasks
end

