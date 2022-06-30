#!/usr/bin/env ruby

require 'thor'
require_relative './corkscrew/corkscrew.rb'

Corkscrew::App.start ARGV
