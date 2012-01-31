#
# Cookbook Name::       zabbix
# Description::         Configures PHP-driven, reverse-proxied Zabbix web frontend using nginx.
# Recipe::              web_nginx
# Author::              Dhruv Bansal (<dhruv@infochimps.com>)
#
# Copyright 2012, Infochimps
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "nginx"

template "/etc/zabbix/php.ini" do
  source 'php.ini.erb'
  owner 'www-data'
  action :create
  notifies :restart, 'service[zabbix_web]', :delayed
end

template "/etc/nginx/sites-available/zabbix.conf" do
  source 'zabbix_web.nginx.conf.erb'
  action :create
  notifies :restart, 'service[nginx]', :delayed
end

nginx_site 'zabbix.conf' do
  action :enable
end

nginx_site 'default' do
  enable false
end

runit_service "zabbix_web"

announce(:zabbix, :web,
         :logs    => { :app => node.zabbix.web.log_dir, :sv => '/etc/sv/zabbix_web/log/main/current' },
         :ports   => {
           :app => {
             :port    => node.zabbix.web.port,
             :service => 'http'
           }
         },
         :daemons => { :php => 'zabbix_web' }
         )
