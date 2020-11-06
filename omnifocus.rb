def osascript(script)
  system 'osascript', *script.split(/\n/).map { |line| ['-e', line] }.flatten
end

def complete_task(task_id)
  osascript <<-END
  tell application "OmniFocus"
      tell default document
          repeat with thisItem in flattened tasks
              set taskId to id of thisItem as text
              if taskId is equal to #{task_id} then
                  mark complete thisItem
                  exit repeat
              end if
          end repeat
      end tell
  end tell
END
end
