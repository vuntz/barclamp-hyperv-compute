raise if not node[:platform] == 'windows'

keystone_settings = KeystoneHelper.keystone_settings(node, :nova)
glance_settings = CrowbarConfig.fetch("openstack", "glance")
cinder_settings = CrowbarConfig.fetch("openstack", "cinder")
neutron_settings = CrowbarConfig.fetch("openstack", "neutron")

dirs = [ node[:openstack][:instances], node[:openstack][:config], node[:openstack][:bin], node[:openstack][:log] ]
dirs.each do |dir|
  directory dir do
    action :create
    recursive true
  end
end

%w{ OpenStackService.exe mkisofs.exe mkisofs_license.txt qemu-img.exe intl.dll libglib-2.0-0.dll libssp-0.dll zlib1.dll }.each do |bin_file|
  cookbook_file "#{node[:openstack][:bin]}/#{bin_file}" do
    source bin_file
  end
end

# Chef 11.4 fails to notify if the path separator is windows like, according to https://tickets.opscode.com/browse/CHEF-4082
# using gsub to replace the windows path separator to linux one
template "#{node[:openstack][:config].gsub(/\\/, "/")}/nova.conf" do
  source "nova.conf.erb"
  variables(
            :glance_server_protocol => glance_settings.fetch("protocol", "http"),
            :glance_server_host => glance_settings.fetch("host", "127.0.0.1"),
            :glance_server_port => glance_settings.fetch("port", 9292),
            :glance_server_insecure => glance_settings.fetch("insecure", false),
            :neutron_protocol => neutron_settings.fetch("protocol", "http"),
            :neutron_server_host => neutron_settings.fetch("host", "127.0.0.1"),
            :neutron_server_port => neutron_settings.fetch("port", 9696),
            :neutron_insecure => neutron_settings.fetch("insecure", false),
            :neutron_service_user => neutron_settings.fetch("service_user", "neutron"),
            :neutron_service_password => neutron_settings.fetch("service_password", ""),
            :neutron_networking_plugin => neutron_settings.fetch("networking_plugin", "ml2"),
            :keystone_settings => keystone_settings,
            :cinder_insecure => cinder_settings.fetch("insecure", false),
            :rabbit_settings => fetch_rabbitmq_settings("nova"),
            :instances_path => node[:openstack][:instances],
            :openstack_location => node[:openstack][:location],
            :openstack_config => node[:openstack][:config],
            :openstack_bin => node[:openstack][:bin],
            :openstack_log => node[:openstack][:log]
           )
end

vlan_start = node[:network][:networks][:nova_fixed][:vlan]
num_vlans = neutron_settings.fetch("num_vlans", 2000)
vlan_end = [vlan_start + num_vlans - 1, 4094].min

template "#{node[:openstack][:config].gsub(/\\/, "/")}/neutron_hyperv_agent.conf" do
  source "neutron_hyperv_agent.conf.erb"
  variables(
            :rabbit_settings => fetch_rabbitmq_settings("nova"),
            :openstack_location => node[:openstack][:location],
            :openstack_log => node[:openstack][:log],
            :neutron_networking_plugin => neutron_settings.fetch("networking_plugin", "ml2"),
            :neutron_ml2_type_drivers => neutron_settings.fetch("ml2_type_drivers", ["gre"]),
            :vlan_start => vlan_start,
            :vlan_end => vlan_end
           )
end

cookbook_file "#{node[:openstack][:config]}/interfaces.template" do
  source "interfaces.template"
end

