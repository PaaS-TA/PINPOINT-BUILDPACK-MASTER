# Encoding: utf-8
require 'java_buildpack/component/base_component'
require 'java_buildpack/util/cache/internet_availability'
require 'java_buildpack/framework'
require 'java_buildpack/util/dash_case'
require 'securerandom'

module JavaBuildpack
  module Framework

    class PinpointAgent < JavaBuildpack::Component::BaseComponent
      
      def MD5hex2base64(str)
        h1=[].clear

        # split the 32 byte hex into a 16 byte array
        16.times{ h1.push(str.slice!(0,2).hex) }
        # pack (C* = unsigned char), (m = base64 encoded output)
        [h1.pack("C*")].pack("m")
      end

      def initialize(context)
        super(context)

        @collector_host, @collector_span_port, @collector_stat_port, @collector_tcp_port, @application_name = find_pinpoint_credentials if supports?

      end


      # (see JavaBuildpack::Component::BaseComponent#detect)
      def detect
        @collector_host ? "#{PinpointAgent.to_s.dash_case}=#{@collector_host}" : nil
      end

      def compile
        resources_dir = Pathname.new(File.expand_path('../../../resources', __dir__)).freeze
        default_conf_dir = resources_dir + @droplet.component_id + 'defaults'

        copy_appd_default_configuration(default_conf_dir)

        @droplet.copy_resources

        #기존 ip, port 값을 읽어와서 인자로 입력하는 것도 가능할 것.
        shell "sed -i s/profiler.collector.ip=127.0.0.1/profiler.collector.ip=#{@collector_host}/ #{@droplet.sandbox}/pinpoint.config"
        shell "sed -i s/profiler.collector.span.port=9996/profiler.collector.span.port=#{@collector_span_port}/ #{@droplet.sandbox}/pinpoint.config"
        shell "sed -i s/profiler.collector.stat.port=9995/profiler.collector.stat.port=#{@collector_stat_port}/ #{@droplet.sandbox}/pinpoint.config"
        shell "sed -i s/profiler.collector.tcp.port=9994/profiler.collector.tcp.port=#{@collector_tcp_port}/ #{@droplet.sandbox}/pinpoint.config"
      end

      def release
        #@agent_id = SecureRandom.urlsafe_base64
        @agent_id = MD5hex2base64(@application_name)

        @droplet.environment_variables
           .add_environment_variable('AGENT_PATH',@droplet.sandbox)# Pinpoint Agent 경로 (파일명 제외한 경로만)

        #.add_system_property('pinpoint.agentId','`cat /proc/sys/kernel/random/uuid| cksum | cut -f1 -d" "`')
        @droplet.java_opts
            .add_javaagent(@droplet.sandbox + 'pinpoint-bootstrap-1.8.4.jar') # agent.jar 파일 경로
            .add_system_property('pinpoint.agentId', @agent_id)
            .add_system_property('pinpoint.applicationName', @application_name)

=begin
        shell "export AGENT_PATH='/app/.java-buildpack/pinpoint_agent'"
        shell "export CATALINA_OPTS='$CATALINA_OPTS -javaagent:$AGENT_PATH/pinpoint-bootstrap-1.6.0-SNAPSHOT.jar'"
        shell 'export CATALINA_OPTS="$CATALINA_OPTS -Dpinpoint.agentId=`cat /proc/sys/kernel/random/uuid| cksum | cut -f1 -d' '` "'
        shell "export CATALINA_OPTS='$CATALINA_OPTS -Dpinpoint.applicationName=#{@application_name}'"
=end


      end

      # Copy default configuration present in resources folder of app_dynamics_agent ver* directories present in sandbox
      #
      # @param [Pathname] default_conf_dir the 'defaults' directory present in app_dynamics_agent resources.
      # @return [Void]
      def copy_appd_default_configuration(default_conf_dir)
        return unless default_conf_dir.exist?

        Dir.glob(@droplet.sandbox + 'ver*') do |target_directory|
          FileUtils.cp_r "#{default_conf_dir}/.", target_directory
        end
      end

      private

      # 'pinpoint'라는 문자를 검출하기 위한 ruby 정규식 형태
      FILTER = /pinpoint/.freeze

      private_constant :FILTER

      # credentials에 입력되는 정보, 서비스 브로커로부터 확인하여 삽입,
      # 'pinpoint' 서비스를 찾았을 때, credentails에서 필요한 값을 리턴
      def find_pinpoint_credentials
        service     = @application.services.find_service FILTER
        credentials = service['credentials']
        collector_host = credentials['collector_host']
        collector_span_port = credentials['collector_span_port']
        collector_stat_port = credentials['collector_stat_port']
        collector_tcp_port = credentials['collector_tcp_port']
        #agent_id = credentials['agent_id']
        #agent_id = SecureRandom.urlsafe_base64
        #application_name = credentials['application_name'] || @application.details['application_uris'][0].split('.')[0]
        application_name = credentials['application_name'] || @application.details['application_uris'][0]
        puts application_name
        application_name = application_name + @configuration['instance_index']
        puts application_name

        [collector_host, collector_span_port, collector_stat_port, collector_tcp_port, application_name]
      end

      # name, label, tags중 하나에 'pinpoint' 라는 문자가 있고 credentials에 collector_host가 있는 경우를 찾는다.
      def supports?
        @application.services.one_service? FILTER, 'collector_host'
      end
    end
  end
end
