##
# A zone.
module Bakery
  class Zone 

    @cfg
    @name
    @cloud 
    @stacks
    @servers
    @components
    @server_names

    attr_accessor :cfg, :name, :cloud, :stacks, :servers, :components, :server_names
    def initialize( name, cfg )
      @cfg = cfg
      @name = name
      @cloud = cloud
      @stacks = {}
      @components = {}
      get_stacks()
      get_components()
    end
    
    def get_cloud_conn()
      @cloud ||= Bakery::HPCloud::Session.new()
    end

    def create_cloud_node( cfg )
      srv = {
        "name" => cfg["hostname"],
        "imageRef" => cfg["image_id"],
        "key_name" => cfg["key_name"],
        "flavorRef" => cfg["flavor_id"]
        #"security_groups" => {
          #"name" => "default"
        #}
      }
      Bakery::Log.debug( "Creating server: %s" % srv.inspect )
      get_cloud_conn.create_server( srv, @cfg["region_name"] )
    end

    def check_key( key_name )
      pub_url = get_cloud_conn.get_catalog_url( "Compute", @cfg["region_name"] )
      keys = get_cloud_conn.get_rest( "%s/os-keypairs" % pub_url )["keypairs"]
      if(keys.select{|key| key["keypair"]["name"] == key_name }.size == 0)
        Bakery::Log.debug( "Key is missing: %s" % key_name )
        get_cloud_conn.create_keypair( key_name, @cfg["region_name"] )

      else
        Bakery::Log.debug( "Key is fine: %s" % key_name )

      end
    end

    def check_limits
      pub_url = get_cloud_conn.get_catalog_url( "Compute", @cfg["region_name"] )
      pp get_cloud_conn.get_rest( "%s/limits" % pub_url )
    end

    ## Pull down the list of servers from the cloud provider.
    def manage_cloud()
      @servers = get_cloud_conn.get_servers( @cfg["region_name"] )["servers"]
      @server_names = @servers.map{|srv| srv["name"] }.sort

      @cfg["stacks"].each do |stack_name,stack_cfg|
        domain_key_name = "%s.%s.%s" % [stack_name, @name, DOMAIN_NAME]
        check_key( domain_key_name )

        stack_cfg = Chef::Mixin::DeepMerge.deep_merge( stack_cfg, @stacks[stack_name] )
        stack_cfg["key_name"] = domain_key_name

        ## Deal with the inputs
        if(stack_cfg.has_key?( "components" ))
          ## Inputs are specifc sub-stacks
          comp = { 
            "comp" => {
              "min" => 1, "max" => 1,
              "flavor_id" => 105,
              "chef" => {
                "tags" => [],
                "run_list" => {}
              }
            }
          }
          stack_cfg["components"].each do |meta_name, comps|
            comps.each do |comp_name|
              comp_chef = @components[comp_name]["resources"][comp_name]["chef"]
              comp["comp"]["chef"] = Chef::Mixin::DeepMerge.deep_merge( comp["comp"]["chef"], comp_chef )
              #end
            end
          end
          Bakery::Log.debug( "Comp: %s" % comp )
          create_resources({
            "name" => "oa",
            "key_name" => domain_key_name,
            "resources" => comp
          })
        end

        #logstash_cfg = @components["logstash"]
        #stack_cfg["inputs"].each do |input_name|
          #Bakery::Log.debug( "Input name: %s" % input_name )
          #stack_cfg = Chef::Mixin::DeepMerge.deep_merge( { "name" => "%s-%s" % [logstash_cfg["name"],input_name] }, logstash_cfg )
          #create_resources( stack_cfg )
        #end
        #next
        
        create_resources( stack_cfg )
      end ## stacks.each
    end

    def get_chef_srv()
      fs_key_file = "%s/.chef/keys/bakery-%s.%s.pem" % [ENV['HOME'], @name, DOMAIN_NAME]
      chef_url = "%s/%s-%s" % [CHEF_URL,@name,DOMAIN_NAME.gsub( /\./,'-' )]
      #Bakery::Log.debug( "ChefUrl: %s" % chef_url )
      @chef_srv ||= Chef::REST.new( chef_url, "bakery", fs_key_file )
    end

    def create_resources( stack_cfg )
      stack_cfg["resources"].each do |resource_name,resource_cfg|
        ## Apply defaults from the zone
        #resource_cfg = Chef::Mixin::DeepMerge.deep_merge( @cfg["defaults"], resource_cfg )
        resource_cfg = Chef::Mixin::DeepMerge.deep_merge( resource_cfg, @cfg["defaults"] )

        resource_cfg["min"].times do |node_id|
          hostname = ("%s-%s%i.%s.%s" % [stack_cfg["name"], resource_name, node_id, @name, DOMAIN_NAME]).gsub( /_/,'-' )
          Bakery::Log.debug( "Hostname: %s" % hostname )
          if(!@server_names.include?( hostname ))
            Bakery::Log.debug( "Host does not exist in cloud" )
            create_cloud_node(resource_cfg.merge({ 'hostname' => hostname, 'key_name' => stack_cfg["key_name"] }))

          else
            ## Do some things to check the state of the node.
            #node = @servers.select{|srv| srv["name"] == hostname }
            get_chef_srv()
            #Bakery::Log.debug( "Chef: %s" % @chef_srv.get_rest( "/nodes" ))
            begin
              node = JSON::parse(@chef_srv.get_rest( "/nodes/%s" % hostname ).to_json)
              #Bakery::Log.debug( "Host: %s"  % node.inspect )
            rescue Net::HTTPServerException => e
              next
            end

            #Bakery::Log.debug( "Cfg: %s"  % resource_cfg["chef"].inspect )
            cfg = resource_cfg

            chef_run_list = (cfg.has_key?( "chef" ) && cfg["chef"].has_key?( "run_list" ) && cfg["chef"]["run_list"] != nil ? cfg["chef"]["run_list"] : [])
            node["run_list"] = chef_run_list
            chef_tags = (cfg.has_key?( "chef" ) && cfg["chef"].has_key?( "tags" ) && cfg["chef"]["tags"] != nil ? cfg["chef"]["tags"] : [])
            node["normal"]["tags"] = chef_tags

            ## Enforce the chef_env bits
            if(node["chef_environment"] == "_default")
              node["chef_environment"] = "prod"
            end

            Bakery::Log.debug( "Tags: %s" % node["normal"]["tags"].inspect )
            Bakery::Log.debug( "ChefEnv: %s" % node["chef_environment"] )
            Bakery::Log.debug( "Runlist: %s" % node["run_list"].inspect )

            #if(options[:dry_run] == false)
            Bakery::Log.debug( "Updating node: %s" % hostname )
            @chef_srv.put_rest( "/nodes/%s" % hostname, node )
          end ## exists?
        end ## min.times
      end ## resources.each
    end

    def get_stacks()
      Dir.glob( "%s/stacks/*.json" % FS_ROOT ).each do |f|
        @stacks[File.basename(f).gsub( /\.json/,'' )] = JSON::parse(File.read( f ))
      end
    end

    def get_components()
      Dir.glob( "%s/stacks/components/*.json" % FS_ROOT ).each do |f|
        @components[File.basename(f).gsub( /\.json/,'' )] = JSON::parse(File.read( f ))
      end
    end

  end ## Stack
end ## Bakery
