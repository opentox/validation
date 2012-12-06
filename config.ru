SERVICE = "validation"
require 'bundler'
Bundler.require
require './application.rb'
run run Sinatra::Application
