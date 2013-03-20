#!/usr/bin/ruby
##
# Load test
require 'rubygems'
require 'pp'
require 'chef'
require 'json'
require 'logger'
require 'optparse'



options = { :dry_run => false, :verbose => false }
OptionParser.new do |opts|
opts.banner = "Usage: baker.rb [options]"

  opts.on( "-v", "--[no-]verbose", "Run verbosely" ) do |v|
    options[:verbose] = v
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

chef_url = "https://fatchef.ksonsoftware.com/organizations/sparkles"

fs_client_key = "%s/.chef/keys/edward.pem" % ENV['HOME']
chef_srv = Chef::REST.new( chef_url, "edward", fs_client_key )

MAX_NUM_THREADS = 100
@num_threads = 0
threads = []

## Create some nodes
if(false)
3000.times do |node_id|
  while(@num_threads >= MAX_NUM_THREADS)
    puts "Sleeping: %i"%  @num_threads
    sleep 1
    puts "Awake: %i" % @num_threads
  end
  @num_threads += 1
  threads << Thread.new do
    begin
      chef_srv.post_rest( "/nodes", { "name" => "test%i" % node_id })
    rescue
    end
    @num_threads -= 1
  end
end
end

## Get nodes
if(true)
threads = []
#while(@num_threads >= MAX_NUM_THREADS)
#puts "Sleeping: %i"%  @num_threads
#sleep 1
#puts "Awake: %i" % @num_threads
#end
#@num_threads += 1
#@num_threads -= 1
all_nodes = chef_srv.get_rest( "/nodes" ).keys
100.times do |thread_id|
  threads << Thread.new do
    300.times do |node_id|
      node_name = all_nodes[rand(all_nodes.size-1)].chomp
      #puts "Getting: [%s]" % node_name
      chef_srv.get_rest( "/nodes/%s" % node_name )

      acls = chef_srv.get_rest( "/nodes/%s/_acl" % node_name )
      #acls["update"]["actors"].push( node_name )
      #chef_srv.put_rest("/%s/%s/_acl/%s" % ['nodes',node_name,'update'], acls )
    end
  end
end
threads.each do |t| t.join end
end

exit

@num_threads = 0

if(true)
threads = []
3000.times do |node_id|
  while(@num_threads >= MAX_NUM_THREADS)
    puts "(clients) Sleeping: %i"%  @num_threads
    sleep 1
    puts "(clients) Awake: %i" % @num_threads
  end
  @num_threads += 1
  threads << Thread.new do
    begin
      chef_srv.post_rest( "/clients", { "name" => "test%i" % node_id })
    rescue
    end
    @num_threads -= 1
  end
end
threads.each do |t| t.join end
end

if(false)
threads = []
300.times do |node_id|
  while(@num_threads >= MAX_NUM_THREADS)
    puts "(roles) Sleeping: %i"%  @num_threads
    sleep 1
    puts "(roles) Awake: %i" % @num_threads
  end
  @num_threads += 1
  threads << Thread.new do
    begin
      chef_srv.post_rest( "/roles", { "name" => "test%i" % node_id })
    rescue
    end
    @num_threads -= 1
  end
end
threads.each do |t| t.join end
end

threads = []
chef_srv.get_rest( "/nodes" ).each do |node_name,url|
  while(@num_threads >= MAX_NUM_THREADS)
    puts "(acl) Sleeping: %i"%  @num_threads
    sleep 1
    puts "(acl) Awake: %i" % @num_threads
  end
  @num_threads += 1
  threads << Thread.new do
    acls = chef_srv.get_rest( "/nodes/%s/_acl" % node_name )
    acls["update"]["actors"].push( node_name )
    chef_srv.put_rest("/%s/%s/_acl/%s" % ['nodes',node_name,'update'], acls )
    @num_threads -= 1
  end
end
threads.each do |t| t.join end

