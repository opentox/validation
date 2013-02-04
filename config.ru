SERVICE = "validation"

require "rubygems"
require "ohm"

require 'bundler'
Bundler.require

require './application.rb'
run Validation::Application

