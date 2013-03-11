#!/usr/bin/ruby
##
# Update the aliases to match hosts in hpcloud servers
#
require 'rubygems'
require 'pp'
require 'json'

f = File.open( "%s/.bashrc.d/hpcloud.com" % ENV['HOME'], "w" )
`hpcloud servers|grep ACTIVE`.split( "\n" ).each do |row|
  fields = row.split
  cmd = "alias %s=\"ssh -i %s/.ssh/keys/aw0_az1_prod0.pem ubuntu@%s\"" % [fields[3],ENV['HOME'],fields[9]] 
  f.puts( cmd )
end
f.close
