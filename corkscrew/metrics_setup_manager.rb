module Corkscrew
  class MetricsSetupManager < Thor
    include Thor::Actions
    include Corkscrew::Helpers::QueryHelpers

    NODE_EXPORTER_VERSION = '1.8.2'
    NVIDIA_GPU_EXPORTER_VERSION = '1.2.1'
    PROMETHEUS_VERSION = '2.54.1'
    GRAFANA_VERSION = '11.2.0'

    def initialize(config, command_runner, syncer, nginx_manager)
      @config = config
      @command_runner = command_runner
      @syncer = syncer
      @nginx_manager = nginx_manager
    end

    no_commands do
      def configure_node
        install_node_exporter
        install_gpu_exporter if ask_default_no('Export GPU metrics too? [yN]')

        add_node_exporter_service

        say 'Make sure to edit /etc/prometheus/prometheus.yml on the host to include this server in `scrape_configs`'
      end

      def configure_host
        install_prometheus
        add_prometheus_service
        install_grafana
        set_up_grafana_nginx if ask_default_yes('Set up nginx config for grafana? [Yn]')

        say 'Now that prometheus and grafana are installed, you need to integrate the two in the web ui:'
        say "First, add a prometheus data source in grafana at #{@grafana_host || 'GRAFANA_HOST'}/connections/datasources/new"
        say "Then, create a dashboard at #{@grafana_host || 'GRAFANA_HOST'}/dashboards/import"
        say "We like https://grafana.com/grafana/dashboards/1860-node-exporter-full/"
      end

      def add_node_exporter_service
        has_service = @command_runner.run_command('systemctl list-units --type=service | grep node_exporter', print_output: false).include?('node_exporter.service')
        if has_service
          say 'Node Exporter service already exists, skipping'
          return
        end

        @syncer.copy_file(File.join(@config.corkscrew_data_dir, 'node_exporter.service'), '/tmp/node_exporter.service')
        @command_runner.run_command('sudo mv /tmp/node_exporter.service /etc/systemd/system/node_exporter.service')
        @command_runner.run_command('sudo systemctl daemon-reload')
        @command_runner.run_command('sudo systemctl enable node_exporter')
        @command_runner.run_command('sudo systemctl start node_exporter')

        say 'Node Exporter service added and started'
      end

      def install_node_exporter
        has_node_exporter = !@command_runner.run_command('ls /etc/node_exporter/node_exporter', print_output: false).include?('No such file')
        if has_node_exporter
          say 'Node Exporter already installed, skipping'
          return
        end

        install_command = [
          "wget -nc https://github.com/prometheus/node_exporter/releases/download/v#{NODE_EXPORTER_VERSION}/node_exporter-#{NODE_EXPORTER_VERSION}.linux-amd64.tar.gz",
          "tar -xzf node_exporter-#{NODE_EXPORTER_VERSION}.linux-amd64.tar.gz",
          "sudo mv node_exporter-#{NODE_EXPORTER_VERSION}.linux-amd64/ /etc/node_exporter"
        ].join(' && ')

        @command_runner.run_command(install_command, cwd: '/tmp')
        say 'Node Exporter installed'
      end

      def install_gpu_exporter
        has_gpu_exporter = @command_runner.run_command('dpkg -l | grep nvidia-gpu-exporter', print_output: false).include?('nvidia-gpu-exporter')
        if has_gpu_exporter
          say 'GPU Exporter already installed, skipping'
          return
        end

        install_command = [
          "wget -nc https://github.com/utkuozdemir/nvidia_gpu_exporter/releases/download/v#{NVIDIA_GPU_EXPORTER_VERSION}/nvidia-gpu-exporter_#{NVIDIA_GPU_EXPORTER_VERSION}_linux_amd64.deb",
          "sudo dpkg -i nvidia-gpu-exporter_#{NVIDIA_GPU_EXPORTER_VERSION}_linux_amd64.deb"
        ].join(' && ')

        @command_runner.run_command(install_command, cwd: '/tmp')
        say 'GPU Exporter installed'
      end

      def install_prometheus
        @command_runner.run_command('ls /etc/prometheus/prometheus')
        has_prometheus = !@command_runner.run_command('ls /etc/prometheus/prometheus', print_output: false).include?('No such file')
        if has_prometheus
          say 'Prometheus already installed, skipping'
          return
        end

        install_command = [
          "wget -nc https://github.com/prometheus/prometheus/releases/download/v#{PROMETHEUS_VERSION}/prometheus-#{PROMETHEUS_VERSION}.linux-amd64.tar.gz",
          "tar -xzf prometheus-#{PROMETHEUS_VERSION}.linux-amd64.tar.gz",
          "sudo mv prometheus-#{PROMETHEUS_VERSION}.linux-amd64/ /etc/prometheus"
        ].join(' && ')

        @command_runner.run_command(install_command, cwd: '/tmp')

        @syncer.copy_file(File.join(@config.corkscrew_data_dir, 'prometheus_default.yml'), '/tmp/prometheus.yml')
        @command_runner.run_command('sudo mv /tmp/prometheus.yml /etc/prometheus/prometheus.yml')

        say 'Prometheus installed'
      end

      def add_prometheus_service
        has_service = @command_runner.run_command('systemctl list-units --type=service | grep prometheus', print_output: false).include?('prometheus.service')
        if has_service
          say 'Prometheus service already exists, skipping'
          return
        end

        @syncer.copy_file(File.join(@config.corkscrew_data_dir, 'prometheus.service'), '/tmp/prometheus.service')
        @command_runner.run_command('sudo mv /tmp/prometheus.service /etc/systemd/system/prometheus.service')
        @command_runner.run_command('sudo systemctl daemon-reload')
        @command_runner.run_command('sudo systemctl enable prometheus')
        @command_runner.run_command('sudo systemctl start prometheus')

        say 'Prometheus service added and started'
      end

      def install_grafana
        has_grafana = @command_runner.run_command('dpkg -l | grep grafana', print_output: false).include?('grafana')
        if has_grafana
          say 'Grafana already installed, skipping'
          return
        end

        @command_runner.run_command('sudo NEEDRESTART_MODE=l apt-get install -y musl')
        @command_runner.run_command("wget -nc https://dl.grafana.com/enterprise/release/grafana-enterprise_#{GRAFANA_VERSION}_amd64.deb", cwd: '/tmp')
        @command_runner.run_command("sudo dpkg -i grafana-enterprise_#{GRAFANA_VERSION}_amd64.deb", cwd: '/tmp')
        @command_runner.run_command('sudo systemctl enable grafana-server')
        @command_runner.run_command('sudo systemctl start grafana-server')

        say 'Grafana installed and started'
      end

      def set_up_grafana_nginx
        has_conf = !@command_runner.run_command('ls /etc/nginx/sites-available/grafana', print_output: false).include?('No such file')
        if has_conf
          say 'Grafana nginx conf already exists, skipping'
          return
        end

        Corkscrew::MetricsSetupManager.source_root(@config.corkscrew_data_dir)
        self.destination_root = '/tmp/'
        @options ||= {} # thor requires this to be defined

        @grafana_port = 3000
        @grafana_host = ask_nonempty('Grafana host (eg grafana.company.com) (reply n to skip nginx setup):')
        if @grafana_host == 'n'
          @grafana_host = nil
          return
        end

        template(
          'grafana_nginx.conf.erb',
          'grafana_nginx.conf'
        )

        @syncer.copy_file(File.join('/tmp/grafana_nginx.conf'), '/tmp/grafana_nginx.conf')
        @command_runner.run_command('sudo mv /tmp/grafana_nginx.conf /etc/nginx/sites-available/grafana')
        @command_runner.run_command('sudo ln -s /etc/nginx/sites-available/grafana /etc/nginx/sites-enabled/grafana')

        @nginx_manager.reload_config
      end

    end
  end
end
