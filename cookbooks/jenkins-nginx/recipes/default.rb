bash 'exe' do
code <<-EOH
sudo wget -q -O - https://jenkins-ci.org/debian/jenkins-ci.org.key | sudo apt-key add -
sudo sh -c 'echo deb http://pkg.jenkins-ci.org/debian binary/ > /etc/apt/sources.list.d/jenkins.list'
sudo apt-get -f install
sudo apt-get update 
EOH
end

package "openjdk-7-jre" 

package "openjdk-7-jdk"

execute 'dpkg' do
command 'sudo dpkg --configure -a'
end

package "jenkins"

service "jenkins" do
  supports [:stop, :start, :restart]
  action [:enable, :start]
end

package 'nginx'

service "nginx" do
 supports status: true
 action [:enable, :start]
end

template '/etc/nginx/sites-enabled/default' do
source 'nginx.erb'
cookbook 'jenkins-nginx'
manage_symlink_source true
owner 'root'
group 'root'
mode '0755'
action:create
end

bash 'key' do
code <<-EOH
sudo chmod 0755 /etc
echo 'JENKINS_ARGS="--webroot=/var/cache/jenkins/war --httpListenAddress=192.168.8.68 --httpPort=$HTTP_PORT -ajp13Port=$AJP_PORT"' >> /etc/default/jenkins
EOH
end
ssl_keyfile = '/etc/nginx/cert.key'
ssl_crtfile = '/etc/nginx/cert.crt'
ssl_signing_conf = '/etc/nginx/cert-ssl.conf'

#ssl_keyfile = "#{node['nginx']['dir']}.key"
#ssl_crtfile = "#{node['nginx']['dir']}.crt"
#ssl_signing_conf = "#{node['nginx']['dir']}-ssl.conf"
unless File.exists?(ssl_keyfile) && File.exists?(ssl_crtfile) && File.exists?(ssl_signing_conf)
  file ssl_keyfile do
    owner "root"
    group "root"
    mode "0644"
    content `/opt/chef/embedded/bin/openssl genrsa 2048`
    not_if { File.exists?(ssl_keyfile) }
  end

  file ssl_signing_conf do
    owner "root"
    group "root"
    mode "0644"
    not_if { File.exists?(ssl_signing_conf) }
    content <<-EOH
  [ req ]
  distinguished_name = req_distinguished_name
  prompt = no
  [ req_distinguished_name ]
  C                      = #{node['nginx']['ssl_country_name']}
  ST                     = #{node['nginx']['ssl_state_name']}
  L                      = #{node['nginx']['ssl_locality_name']}
  O                      = #{node['nginx']['ssl_company_name']}
  OU                     = #{node['nginx']['ssl_organizational_unit_name']}
  CN                     = #{node['nginx']['server_name']}
  emailAddress           = #{node['nginx']['ssl_email_address']}
  EOH
  end

  ruby_block "create crtfile" do
    block do
      r = Chef::Resource::File.new(ssl_crtfile, run_context)
      r.owner "root"
      r.group "root"
      r.mode "0755"
      r.content `/opt/chef/embedded/bin/openssl req -config '#{ssl_signing_conf}' -new -x509 -nodes -sha1 -days 3650 -key #{ssl_keyfile}`
      r.not_if { File.exists?(ssl_crtfile) }
      r.run_action(:create)
    end
  end
end

node.default['nginx']['ssl_certificate'] ||= ssl_crtfile
node.default['nginx']['ssl_certificate_key'] ||= ssl_keyfile

#
# Cookbook Name:: jenkins-nginx
# Recipe:: default
#
# Copyright (c) 2016 The Authors, All Rights Reserved.
