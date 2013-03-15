#!/usr/bin/ruby
##
# Update the aliases to match hosts in hpcloud servers
#
require 'rubygems'
require 'pp'
require 'json'

zone_key_name = "prod2.ksonsoftware.com.pem"

f = File.open( "%s/.bashrc.d/hpcloud.com" % ENV['HOME'], "w" )
fhosts = File.open( "hosts_all", "w" )
`hpcloud servers|grep ACTIVE`.split( "\n" ).each do |row|
  fields = row.split
  cmd = "alias %s=\"ssh -i %s/.ssh/keys/%s ubuntu@%s\"" % [fields[3],ENV['HOME'],zone_key_name,fields[9]] 
  f.puts( cmd )
  fhosts.puts( fields[9] )
end
f.close
fhosts.close
