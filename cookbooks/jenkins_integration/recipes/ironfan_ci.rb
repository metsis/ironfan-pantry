#
# Cookbook Name:: jenkins_integration
# Recipe:: ironfan_ci
#
# Copyright 2012, Infochimps, Inc.
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

#
# Environmental Setup
#

ssh_dir                 = node[:jenkins][:server][:home_dir] + '/.ssh'
directory ssh_dir do
  owner         node[:jenkins][:server][:user]
  group         node[:jenkins][:server][:group]
  mode          '0700'
end

# Set up the correct public key
private_key_filename     = ssh_dir + '/id_rsa'
file private_key_filename do
  owner         node[:jenkins][:server][:user]
  group         node[:jenkins][:server][:group]
  content       node[:jenkins_integration][:ironfan_ci][:deploy_key]
  mode          '0600'
  notifies      :run, 'execute[Regenerate id_rsa.pub]', :immediately
end
execute 'Regenerate id_rsa.pub' do
  user          node[:jenkins][:server][:user]
  group         node[:jenkins][:server][:group]
  cwd           ssh_dir
  command       "ssh-keygen -y -f id_rsa -N'' -P'' > id_rsa.pub"
  action        :nothing
end

# Add Github's fingerprint to known_hosts
cookbook_file ssh_dir + '/github.fingerprint' do
  user          node[:jenkins][:server][:user]
  group         node[:jenkins][:server][:group]
  notifies      :run, 'execute[Get familiar with Github]', :immediately
end
execute 'Get familiar with Github' do
  user          node[:jenkins][:server][:user]
  group         node[:jenkins][:server][:group]
  cwd           ssh_dir
  command       "cat github.fingerprint >> known_hosts"
  action        :nothing
end

# Setup jenkins user to make commits
template node[:jenkins][:server][:home_dir] + '/.gitconfig' do
  source        '.gitconfig.erb'
  owner         node[:jenkins][:server][:user]
  group         node[:jenkins][:server][:group]
end

# Lock access down to local user accounts
# FIXME: This is only the vaguest of security, very unconfigurable,
#   and really should be done over HTTPS to prevent pw hash sniffing.
if node[:jenkins_integration][:security] == "local_users"
  group "shadow" do
    action :modify
    members node[:jenkins][:server][:user]
    append true
  end
  template "#{node[:jenkins][:server][:home_dir]}/config.xml" do
    source        "core.config.xml.erb"
    owner         node[:jenkins][:server][:user]
    group         node[:jenkins][:server][:group]
  end
end

# FIXME: fucking omnibus
file node[:jenkins][:server][:home_dir] + '/.profile' do
  content       'export PATH=/opt/chef/embedded/bin/:$PATH'
  owner         node[:jenkins][:server][:user]
  group         node[:jenkins][:server][:group]
end

#
# Jenkins Jobs
#

# Make sure that the test homebase is the first homebase
node.set[:jenkins_integration][:ironfan_ci][:homebases] = \
  ( node[:jenkins_integration][:ironfan_ci][:homebases].to_a.unshift 
    default[:jenkins_integration][:ironfan_ci][:test_homebase] ).uniq

# 1. Check out every homebase and pantry, getting all branches
# 2. Enqueue testing on each of them
# 3. Sync changes to testing environment (including versions) [sync_changes.sh]
# 4. Launch test instance [launch_instance.sh]
# 5. Stage homebases and pantries
#   a. Homebases: Upload cookbook and freeze at that version
#   b. All: Commit testing cookbook versions to staging
shared_templates = %w[ shared.inc launch.inc checkout.sh cookbook_versions.rb.h ]
jenkins_job "Ironfan" do
  templates     shared_templates
  tasks         %w[ enqueue_tests.sh cookbook_changes.sh
                    sync_changes.sh launch_instance.sh stage_all.sh ]
  if node[:jenkins_integration][:ironfan_ci][:broken]
    downstream [ "Ironfan - known broken" ]
  end
end

# Launch known broken instance [launch_broken.sh]
if node[:jenkins_integration][:ironfan_ci][:broken]
  jenkins_job "Ironfan - known broken" do
    templates     shared_templates
    tasks       %w[ launch_broken.sh ]
  end
end

