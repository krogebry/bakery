##
# config

DOMAIN_NAME = "ksonsoftware.com"

## Configuration management bits
module Bakery
  module Config
    attr_accessor :chef_url, :cloud_url
  end
end

CHEF_URL = "https://15.185.102.107/organizations/"
CLOUD_URL = "https://region-a.geo-1.identity.hpcloudsvc.com:35357/v2.0/tokens"
