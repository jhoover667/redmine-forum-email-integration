desc 'Load Redmine default configuration data'

namespace :redmine do
  task :load_default_data => :environment do
    include GLoc
    set_language_if_valid('en')
    puts
    
    while true
      print "Select language: "
      print GLoc.valid_languages.sort {|x,y| x.to_s <=> y.to_s }.join(", ")
      print " [#{GLoc.current_language}] "
      lang = STDIN.gets.chomp!
      break if lang.empty?
      break if set_language_if_valid(lang)
      puts "Unknown language!"
    end
    
    puts "===================================="
    
    begin
      Redmine::DefaultData::Loader.load(current_language)
      puts "Default configuration data loaded."
    rescue => error
      puts "Error: " + error
      puts "Default configuration data was not loaded."
    end
  end
end
