# Creating symbolic links from spark jars in the lib/ directory where spark is installed to
# the directory containing yarn jars in hadoop. Hopefully, yarn will pick up these jars and add them
# to the HADOOP_CLASSPATH :)
# One potential problem could be if you install.hadoop_spark.as a different user than the default user 'yarn'.
# Then the symbolic link may not be able to be created due to a lack of file privileges.
#

home = node['hops']['hdfs']['user_home']
private_ip=my_private_ip()


#
# local directory logs
#
directory node['hadoop_spark']['local']['dir'] do
  owner node['hadoop_spark']['user']
  group node['hops']['group']
  mode "770"
  action :create
  recursive true
  not_if { File.directory?("#{node['hadoop_spark']['local']['dir']}") }
end


# Only the first NN needs to create the directories
if private_ip.eql? node['hadoop_spark']['yarn']['private_ips'][0]

  hops_hdfs_directory "#{home}" do
    action :create_as_superuser
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1777"
  end


  hops_hdfs_directory "#{home}/#{node['hadoop_spark']['user']}" do
    action :create_as_superuser
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1777"
  end

  hops_hdfs_directory "#{home}/#{node['hadoop_spark']['user']}/eventlog" do
    action :create_as_superuser
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1775"
  end

  hops_hdfs_directory "#{home}/#{node['hadoop_spark']['user']}/spark-warehouse" do
    action :create_as_superuser
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1775"
  end

  hops_hdfs_directory "#{home}/#{node['hadoop_spark']['user']}/share/lib" do
    action :create_as_superuser
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1775"
  end

  # Package Spark jars
  spark_packaged = "#{node['hadoop_spark']['home']}/.hadoop_spark.packaged_#{node['hadoop_spark']['version']}"

  bash 'extract_hadoop_spark' do
        user "root"
        code <<-EOH
                set -e
                cd #{node['hadoop_spark']['home']}/jars
                zip -o #{node['hadoop_spark']['yarn']['archive']} *
		cd ..
                mv jars/#{node['hadoop_spark']['yarn']['archive']} .
                mkdir -p #{node['hadoop_spark']['home']}/logs
                touch #{spark_packaged}
                cd ..
                chown -R #{node['hadoop_spark']['user']}:#{node['hadoop_spark']['group']} #{node['hadoop_spark']['home']}
                chmod 750 #{node['hadoop_spark']['home']}
                # make the logs dir writeable by the sparkhistoryserver (runs as user 'hdfs')
                chmod 770 #{node['hadoop_spark']['home']}/logs
        EOH
     not_if { ::File.exists?( spark_packaged ) }
  end


  hops_hdfs_directory "#{node['hadoop_spark']['home']}/#{node['hadoop_spark']['yarn']['archive']}" do
    action :put_as_superuser
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1775"
    dest "#{node['hadoop_spark']['yarn']['archive_hdfs']}"
  end

  hops_hdfs_directory "#{node['hadoop_spark']['home']}/python/lib/#{node['hadoop_spark']['yarn']['pyspark_archive']}" do
    action :put_as_superuser
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1775"
    dest "#{node['hadoop_spark']['yarn']['pyspark_archive_hdfs']}"
  end

  hops_hdfs_directory "#{node['hadoop_spark']['home']}/python/lib/#{node['hadoop_spark']['yarn']['py4j_archive']}" do
    action :put_as_superuser
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1775"
    dest "#{node['hadoop_spark']['yarn']['py4j_archive_hdfs']}"
  end


  hopsworks_user=node['hops']['hdfs']['user']
  hopsworks_group=node['hops']['group']

  if node.attribute?('hopsworks') == true
    if node['hopsworks'].attribute?('user') == true
      hopsworks_user = node['hopsworks']['user']
    end
  end

  hopsUtil=File.basename(node['hops']['hopsutil']['url'])

  remote_file "#{Chef::Config['file_cache_path']}/#{hopsUtil}" do
    source node['hops']['hopsutil']['url']
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1775"
    action :create
  end

  hops_hdfs_directory "#{Chef::Config['file_cache_path']}/#{hopsUtil}" do
    action :put_as_superuser
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1755"
    dest "/user/#{node['hadoop_spark']['user']}/#{node['hops']['hopsutil_jar']}"
  end


  hopsKafkaJar=File.basename(node['hops']['hops_spark_kafka_example']['url'])

  remote_file "#{Chef::Config['file_cache_path']}/#{hopsKafkaJar}" do
    source node['hops']['hops_spark_kafka_example']['url']
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1775"
    action :create
  end

  hops_hdfs_directory "#{Chef::Config['file_cache_path']}/#{hopsKafkaJar}" do
    action :put_as_superuser
    owner hopsworks_user
    group node['hops']['group']
    mode "1755"
    dest "/user/#{hopsworks_user}/#{node['hops']['examples_jar']}"
  end

end

#
# Support Intel MKL library for matrix computations
# https://blog.cloudera.com/blog/2017/02/accelerating-apache-spark-mllib-with-intel-math-kernel-library-intel-mkl/
#
case node['platform_family']
when "debian"

  package "libnetlib-java" do
    action :install
  end

when "rhel"

  # TODO - add 'netlib-java'
end


jarFile="spark-#{node['hadoop_spark']['version']}-yarn-shuffle.jar"


link "#{node['hops']['base_dir']}/share/hadoop/yarn/lib/#{jarFile}" do
  owner node['hops']['yarn']['user']
  group node['hops']['group']
  to "#{node['hadoop_spark']['base_dir']}/yarn/#{jarFile}"
end


begin
  influxdb_ip = private_recipe_ip("hopsmonitor","default")
rescue
  Chef::Log.error "could not find the influxdb ip!"
end

template "#{node['hadoop_spark']['base_dir']}/conf/metrics.properties" do
  source "metrics.properties.erb"
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  mode 0750
  action :create
  variables({
        :influxdb_ip => influxdb_ip
  })
end

hops_hdfs_directory "#{node['hadoop_spark']['base_dir']}/conf/metrics.properties"  do
  action :put_as_superuser
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  mode "1775"
  dest "/user/#{node['hadoop_spark']['user']}/metrics.properties"
end

begin
  logstash_ip = private_recipe_ip("hopslog","default")
rescue
  logstash_ip = node['hostname']
  Chef::Log.warn "could not find the Logstash ip!"
end


template"#{node['hadoop_spark']['conf_dir']}/log4j.properties" do
  source "app.log4j.properties.erb"
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  mode 0650
  variables({
        :logstash_ip => logstash_ip
           })

end

  hops_hdfs_directory "#{node['hadoop_spark']['home']}/conf/metrics.properties" do
    action :put_as_superuser
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1775"
    dest "/user/#{node['hops']['hdfs']['user']}/metrics.properties"
  end

  hops_hdfs_directory "#{node['hadoop_spark']['home']}/conf/log4j.properties" do
    action :put_as_superuser
    owner node['hadoop_spark']['user']
    group node['hops']['group']
    mode "1775"
    dest "/user/#{node['hops']['hdfs']['user']}/log4j.properties"
  end


bash 'install_pydoop' do
        user "root"
        code <<-EOH
           set -e
           export HADOOP_HOME=#{node['hops']['base_dir']}
           export HADOOP_CONF_DIR=#{node['hops']['home']}/etc/hadoop
           pip install --upgrade pydoop
        EOH
end
