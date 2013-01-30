#
# Cookbook Name:: etherpad-lite
# Recipe:: default
#
# Copyright 2011, Steffen Gebert / TYPO3 Association
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

##################
# nodejs & npm


include_recipe "nodejs"

include_recipe "npm"


##################


# Create etherpad-lite User
user "etherpad-lite" do
  comment "etherpad-lite User"
  shell "/bin/bash"
end

packages = [
  'curl',
  'python',
  'libssl-dev',
  'git'
]

case node[:platform]
when "debian", "ubuntu"
  packages.each do |pkg|
    package pkg do
      action :upgrade
  end
end
when "centos"
  log "No centos support yet"
end

#################
# etherpad-lite

# Create directories
directory "/var/log/etherpad-lite" do
  owner "etherpad-lite"
  group "etherpad-lite"
  mode "755"
end

directory "/usr/local/etherpad-lite" do
  owner "etherpad-lite"
  group "etherpad-lite"
  mode "755"
  notifies :run, "script[install_etherpad-lite]"
end

# installation of etherpad-lite
script "install_etherpad-lite" do
  interpreter "bash"
  user "etherpad-lite"
  code <<-EOH
  git clone "https://github.com/ether/etherpad-lite.git" /usr/local/etherpad-lite
  EOH
  #action :nothing
  notifies :run, "script[install_dependencies]"
  notifies :start, "service[etherpad-lite]"
  not_if do
    File.exists?("/usr/local/etherpad-lite/README.md")
  end
end

script "install_dependencies" do
  interpreter "bash"
  user "root"
  cwd "/usr/local/etherpad-lite"
  action :nothing
  code <<-EOH
  bin/installDeps.sh
  chmod 755 /usr/local/lib/node*
  EOH
end


############################
# etherpad-lite mysql setup

# Install MySQL server

include_recipe "database"
include_recipe "mysql::server"

# generate the password
::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)
node.set_unless[:etherpadlite][:database][:password] = secure_password

mysql_connection_info = {:host => "localhost", :username => 'root', :password => node['mysql']['server_root_password']}

# create etherpad-lite database
mysql_database 'etherpadlite' do
  connection mysql_connection_info
  action :create
  notifies :create, "template[/usr/local/etherpad-lite/settings.json]"
end

# Grant etherpad-lite
mysql_database_user 'etherpadlite' do
  connection mysql_connection_info
  password node[:etherpadlite][:database][:password]
  database_name 'etherpadlite'
  host node[:etherpadlite][:database][:host]
  privileges ["ALL PRIVILEGES"]
  action :grant
end

mysql_database_user 'etherpadlite' do
  connection mysql_connection_info
  password node[:etherpadlite][:database][:password]
  database_name 'etherpadlite'
  host "127.0.0.1"
  privileges ["ALL PRIVILEGES"]
  action :grant
end

template "/usr/local/etherpad-lite/settings.json" do
  source "settings.json.erb"
  owner "etherpad-lite"
  group "etherpad-lite"
  mode "644"
  notifies :restart, "service[etherpad-lite]"
end

node.set_unless[:etherpadlite][:settings][:apikey] = secure_password
file "/usr/local/etherpad-lite/APIKEY.txt" do
  content node[:etherpadlite][:settings][:apikey]
end

# Install abiword package, if requested
if node[:etherpadlite][:settings][:abiword]
  package "abiword" do
      action :upgrade
  end
end


# Install Init script
template "/etc/init.d/etherpad-lite" do
  source "etherpad-lite.init.erb"
  owner "root"
  group "root"
  mode "754"
end

service "etherpad-lite" do
  supports :status => true, :start => true, :stop => true
  action [ :start, :enable ]
end

include_recipe "firewall"

# nginx reverse proxy
if node[:etherpadlite][:proxy][:enable]
	include_recipe "nginx"
	
    template "/etc/nginx/sites-available/#{node.etherpadlite.proxy.hostname}" do
      source "nginx-site.erb"
      notifies :restart, "service[nginx]"
    end

    nginx_site "#{node.etherpadlite.proxy.hostname}" do
      enable true
    end

    firewall_rule "http" do
      port 80
      action :allow
    end
else
  firewall_rule "etherpad" do
    port node[:etherpadlite][:listen][:port]
    action :allow
  end
end


