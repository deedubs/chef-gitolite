#
# Cookbook Name:: gitolite
# Recipe:: default
#
# Copyright 2011, RocketLabs Development
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

package 'git'

bash 'install_gitolite' do
  cwd "/tmp"
  code <<-EOH
    git clone git://github.com/sitaramc/gitolite gitolite-source
    cd gitolite-source
    git checkout -t origin/pu
    mkdir -p /usr/local/share/gitolite/conf /usr/local/share/gitolite/hooks
    src/gl-system-install /usr/local/bin /usr/local/share/gitolite/conf /usr/local/share/gitolite/hooks
  EOH
  creates '/usr/local/bin/gl-setup'
end

gitolite_instances = node['gitolite']

gitolite_instances.each do |instance|
  username = instance['name']

  user username do
    comment "#{username} Gitolite User"
    home "/home/#{username}"
    shell "/bin/bash"
  end

  directory "/home/#{username}" do
    owner username
    action :create
  end

  admin_name = instance['admin']
  admin_ssh_key = data_bag_item('users',admin_name)['ssh_key']

  file "/tmp/gitolite-#{admin_name}.pub" do
    owner username
    content admin_ssh_key
  end

  template "/home/#{username}/.gitolite.rc" do
    owner username
    source "gitolite.rc.erb"
    action :create
  end

  execute "installing_gitolite_for" do
    user username
    command "/usr/local/bin/gl-setup /tmp/gitolite-#{admin_name}.pub"
    environment ({'HOME' => "/home/#{username}"})
  end
end




