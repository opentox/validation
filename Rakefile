require 'rubygems'
require 'rake'



REPORT_GEMS = [  'opentox-ruby', 'ruby-plot', 'rinruby', 'dm-core', 'dm-serializer', 'dm-timestamps',
  'dm-types', 'dm-migrations', 'dm-validations', 'dm-sqlite-adapter', 'benchmark']
VALIDATION_GEMS = [  'opentox-ruby', 'ruby-plot']

GEM_VERSIONS = { "ruby-plot" => "= 0.0.2" }
GEM_INSTALL_OPTIONS = {}

#GEM_VERSIONS = { "activerecord" => "= 2.3.8", "activesupport" => "= 2.3.8", "ar-extensions" => "= 0.9.2", "ruby-plot" => "= 0.0.2" }
## this is needed because otherwihse ar-extensions adds activesupport 3.0.0 which confuses things
#GEM_INSTALL_OPTIONS = { "ar-extensions" => "--ignore-dependencies" }

desc "Install required gems"
task :install_gems do
  (REPORT_GEMS + VALIDATION_GEMS).uniq.each do |g|
    begin
      if GEM_VERSIONS.has_key?(g)
        print "> gem "+g+", '"+GEM_VERSIONS[g]+"' .. "
        gem g, GEM_VERSIONS[g]
      else
        print "> gem "+g+" .. "
        gem g
      end
      puts "ok"
    rescue LoadError => ex
      puts "NOT FOUND"
      options = ""
      options += "--version '"+GEM_VERSIONS[g]+"' " if GEM_VERSIONS.has_key?(g)
      options += GEM_INSTALL_OPTIONS[g]+" " if GEM_INSTALL_OPTIONS.has_key?(g)
      #cmd = "sudo env PATH=$PATH gem install "+options+" "+g
      cmd = "gem install "+options+" "+g
      puts "installing gem, this may take some time..."
      puts cmd
      IO.popen(cmd){ |f| puts f.gets }
    end
  end
end

desc "Perform unit tests"
task :test do
  require 'test/unit_test.rb'
end

=begin

desc "Installs gems and inits db migration"
task :init => [:install_gems, :migrate] do
  #do nothing
end


desc "load config"
task :load_config do
  require 'yaml'
  ENV['RACK_ENV'] = 'production' unless ENV['RACK_ENV']
  basedir = File.join(ENV['HOME'], ".opentox")
  config_dir = File.join(basedir, "config")
  config_file = File.join(config_dir, "#{ENV['RACK_ENV']}.yaml")
  if File.exist?(config_file)
    CONFIG = YAML.load_file(config_file)
    raise "could not load config, config file: "+config_file.to_s unless CONFIG
  end
  puts "config loaded"
end

# USE VERSION 0 instead
#desc "Clear database"
#task :clear_db => :load_config  do
#  if  CONFIG[:database][:adapter]=="mysql"
#    clear = nil
#    IO.popen("locate clear_mysql.sh"){ |f| clear=f.gets.chomp("\n") }
#    raise "clear_mysql.sh not found" unless clear
#    cmd = clear+" "+CONFIG[:database][:username]+" "+CONFIG[:database][:password]+" "+CONFIG[:database][:database]
#    IO.popen(cmd){ |f| puts f.gets }
#  else
#    raise "clear not implemented for database-type: "+CONFIG[:database][:adapter]
#  end
#end

desc "Migrate the database through scripts in db/migrate. Target specific version with VERSION=x"
task :migrate => :load_config do
  [ 'rubygems', 'active_record', 'logger' ].each{ |l| require l }
  puts "database config: "+@@config[:database].inspect.to_s
  ActiveRecord::Base.establish_connection(  
       :adapter => CONFIG[:database][:adapter],
       :host => CONFIG[:database][:host],
       :database => CONFIG[:database][:database],
       :username => CONFIG[:database][:username],
       :password => CONFIG[:database][:password]
       )  
  ActiveRecord::Base.logger = Logger.new($stdout)
  ActiveRecord::Migrator.migrate('db/migrate', ENV["VERSION"] ? ENV["VERSION"].to_i : 2 )
end

=end

