require_relative "../../../base"

require Vagrant.source_root.join("lib/vagrant/util/deep_merge")
require Vagrant.source_root.join("plugins/providers/docker/driver")

describe VagrantPlugins::DockerProvider::Driver::Compose do
  let(:cmd_executed) { @cmd }
  let(:cid)          { 'side-1-song-10' }
  let(:docker_yml){ double("docker-yml", path: "/tmp-file") }
  let(:machine){ double("machine", env: env, name: :docker_1, id: :docker_id, provider_config: provider_config) }
  let(:compose_configuration){ {} }
  let(:provider_config) do
    double("provider-config",
      compose: true,
      compose_configuration: compose_configuration
    )
  end
  let(:env) do
    double("env",
      cwd: Pathname.new("/compose/cwd"),
      local_data_path: local_data_path
    )
  end
  let(:composition_content){ "--- {}\n" }
  let(:composition_path) do
    double("composition-path",
      to_s: "docker-compose.yml",
      exist?: true,
      read: composition_content,
      delete: true
    )
  end
  let(:data_directory){ double("data-directory", join: composition_path) }
  let(:local_data_path){ double("local-data-path") }
  let(:compose_execute_up){ ["docker-compose", "-f", "docker-compose.yml", "-p", "cwd", "up", "--remove-orphans", "-d", {}] }


  subject{ described_class.new(machine) }

  before do
    allow(Vagrant::Util::Which).to receive(:which).and_return("/dev/null/docker-compose")
    allow(env).to receive(:lock).and_yield
    allow(Pathname).to receive(:new).with(local_data_path).and_return(local_data_path)
    allow(local_data_path).to receive(:join).and_return(data_directory)
    allow(data_directory).to receive(:mkpath)
    allow(FileUtils).to receive(:mv)
    allow(Tempfile).to receive(:new).with("vagrant-docker-compose").and_return(docker_yml)
    allow(docker_yml).to receive(:write)
    allow(docker_yml).to receive(:close)
    subject.stub(:execute) do |*args|
      args.delete_if{|i| i.is_a?(Hash) }
      @cmd = args.join(' ')
    end
  end

  describe '#create' do
    let(:params) { {
      image:      'jimi/hendrix:eletric-ladyland',
      cmd:        ['play', 'voodoo-chile'],
      ports:      '8080:80',
      volumes:    '/host/path:guest/path',
      detach:     true,
      links:      [[:janis, 'joplin'], [:janis, 'janis']],
      env:        {key: 'value'},
      name:       cid,
      hostname:   'jimi-hendrix',
      privileged: true
    } }

    before { expect(subject).to receive(:execute).with(*compose_execute_up) }
    after { subject.create(params) }

    it 'sets container name' do
      expect(docker_yml).to receive(:write).with(/#{machine.name}/)
    end

    it 'forwards ports' do
      expect(docker_yml).to receive(:write).with(/#{params[:ports]}/)
    end

    it 'shares folders' do
      expect(docker_yml).to receive(:write).with(/#{params[:volumes]}/)
    end

    it 'links containers' do
      params[:links].each do |link|
        expect(docker_yml).to receive(:write).with(/#{link}/)
        subject.create(params)
      end
    end

    it 'sets environmental variables' do
      expect(docker_yml).to receive(:write).with(/key.*value/)
    end

    it 'is able to run a privileged container' do
      expect(docker_yml).to receive(:write).with(/privileged/)
    end

    it 'sets the hostname if specified' do
      expect(docker_yml).to receive(:write).with(/#{params[:hostname]}/)
    end

    it 'executes the provided command' do
      expect(docker_yml).to receive(:write).with(/#{params[:image]}/)
    end
  end

  describe '#created?' do
    let(:result) { subject.created?(cid) }

    it 'performs the check on all containers list' do
      subject.created?(cid)
      expect(cmd_executed).to match(/docker ps \-a \-q/)
    end

    context 'when container exists' do
      before { subject.stub(execute: "foo\n#{cid}\nbar") }
      it { expect(result).to be_true }
    end

    context 'when container does not exist' do
      before { subject.stub(execute: "foo\n#{cid}extra\nbar") }
      it { expect(result).to be_false }
    end
  end

  describe '#pull' do
    it 'should pull images' do
      subject.should_receive(:execute).with('docker', 'pull', 'foo')
      subject.pull('foo')
    end
  end

  describe '#running?' do
    let(:result) { subject.running?(cid) }

    it 'performs the check on the running containers list' do
      subject.running?(cid)
      expect(cmd_executed).to match(/docker ps \-q/)
      expect(cmd_executed).to_not include('-a')
    end

    context 'when container exists' do
      before { subject.stub(execute: "foo\n#{cid}\nbar") }
      it { expect(result).to be_true }
    end

    context 'when container does not exist' do
      before { subject.stub(execute: "foo\n#{cid}extra\nbar") }
      it { expect(result).to be_false }
    end
  end

  describe '#privileged?' do
    it 'identifies privileged containers' do
      subject.stub(inspect_container: {'HostConfig' => {"Privileged" => true}})
      expect(subject).to be_privileged(cid)
    end

    it 'identifies unprivileged containers' do
      subject.stub(inspect_container: {'HostConfig' => {"Privileged" => false}})
      expect(subject).to_not be_privileged(cid)
    end
  end

  describe '#start' do
    context 'when container is running' do
      before { subject.stub(running?: true) }

      it 'does not start the container' do
        subject.should_not_receive(:execute).with('docker', 'start', cid)
        subject.start(cid)
      end
    end

    context 'when container is not running' do
      before { subject.stub(running?: false) }

      it 'starts the container' do
        subject.should_receive(:execute).with('docker', 'start', cid)
        subject.start(cid)
      end
    end
  end

  describe '#stop' do
    context 'when container is running' do
      before { subject.stub(running?: true) }

      it 'stops the container' do
        subject.should_receive(:execute).with('docker', 'stop', '-t', '1', cid)
        subject.stop(cid, 1)
      end

      it "stops the container with the set timeout" do
        subject.should_receive(:execute).with('docker', 'stop', '-t', '5', cid)
        subject.stop(cid, 5)
      end
    end

    context 'when container is not running' do
      before { subject.stub(running?: false) }

      it 'does not stop container' do
        subject.should_not_receive(:execute).with('docker', 'stop', '-t', '1', cid)
        subject.stop(cid, 1)
      end
    end
  end

  describe '#rm' do
    context 'when container has been created' do
      before { subject.stub(created?: true) }

      it 'removes the container' do
        expect(subject).to receive(:execute).with("docker-compose", "-f", "docker-compose.yml", "-p", "cwd", "rm", "-f", "docker_1", {})
        subject.rm(cid)
      end
    end

    context 'when container has not been created' do
      before { subject.stub(created?: false) }

      it 'does not attempt to remove the container' do
        expect(subject).not_to receive(:execute).with("docker-compose", "-f", "docker-compose.yml", "-p", "cwd", "rm", "-f", "docker_1", {})
        subject.rm(cid)
      end
    end
  end

  describe '#inspect_container' do
    let(:data) { '[{"json": "value"}]' }

    before { subject.stub(execute: data) }

    it 'inspects the container' do
      subject.should_receive(:execute).with('docker', 'inspect', cid)
      subject.inspect_container(cid)
    end

    it 'parses the json output' do
      expect(subject.inspect_container(cid)).to eq('json' => 'value')
    end
  end

  describe '#all_containers' do
    let(:containers) { "container1\ncontainer2" }

    before { subject.stub(execute: containers) }

    it 'returns an array of all known containers' do
      subject.should_receive(:execute).with('docker', 'ps', '-a', '-q', '--no-trunc')
      expect(subject.all_containers).to eq(['container1', 'container2'])
    end
  end

  describe '#docker_bridge_ip' do
    let(:containers) { " inet 123.456.789.012/16 " }

    before { subject.stub(execute: containers) }

    it 'returns an array of all known containers' do
      subject.should_receive(:execute).with('/sbin/ip', '-4', 'addr', 'show', 'scope', 'global', 'docker0')
      expect(subject.docker_bridge_ip).to eq('123.456.789.012')
    end
  end
end
