#!/usr/bin/ruby
##
# Update the aliases to match hosts in hpcloud servers
#
require 'rubygems'
require 'pp'
require 'json'


f = File.open( "%s/.bashrc.d/hpcloud.com" % ENV['HOME'], "w" )
fhosts = File.open( "./tmp/hosts_all", "w" )
["prod0","prod1","prod2"].each do |env_name|
  zone_key_name = "%s.ksonsoftware.com" % env_name
  fhosts.puts( "## %s" % zone_key_name )
  `./bin/tune_env #{env_name} ; hpcloud servers|grep ACTIVE|grep #{zone_key_name}`.split( "\n" ).each do |row|
   fields = row.split
   #cmd = "alias %s=\"ssh -i %s/.ssh/keys/%s ubuntu@%s\"" % [fields[3],ENV['HOME'],zone_key_name,fields[9]] 
   cmd = "alias %s=\"ssh ubuntu@%s\"" % [fields[3],fields[9]] 
   f.puts( cmd )
   fhosts.puts( fields[9] )
  end
end
f.close
fhosts.close
