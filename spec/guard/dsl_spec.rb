require 'spec_helper'
require 'guard/plugin'

describe Guard::DSL do

  let(:local_guardfile) { File.join(Dir.pwd, 'Guardfile') }
  let(:home_guardfile) { File.expand_path(File.join('~', '.Guardfile')) }
  let(:home_config) { File.expand_path(File.join('~', '.guard.rb')) }
  before do
    stub_const 'Guard::Dummy', Class.new(Guard::Plugin)
    ::Guard.stub(:setup_interactor)
    ::Guard.setup
    ::Guard.stub(:guards).and_return([mock('Guard::Dummy')])
    ::Guard::Notifier.stub(:notify)
  end

  def self.disable_user_config
    before { File.stub(:exist?).with(home_config) { false } }
  end

  describe '.evaluate_guardfile' do
    it 'displays an error message when Guardfile is not valid' do
      Guard::UI.should_receive(:error).with(/Invalid Guardfile, original error is:/)

      described_class.evaluate_guardfile(:guardfile_contents => invalid_guardfile_string )
    end

    it 'displays an error message when no Guardfile is found' do
      described_class.stub(:guardfile_default_path).and_return('no_guardfile_here')
      Guard::UI.should_receive(:error).with('No Guardfile found, please create one with `guard init`.')
      lambda { described_class.evaluate_guardfile }.should raise_error
    end

    it 'doesn\'t display an error message when no Guard plugins are defined in Guardfile' do
      ::Guard::Dsl.stub!(:instance_eval_guardfile)
      ::Guard.stub!(:guards).and_return([])
      Guard::UI.should_not_receive(:error)
      described_class.evaluate_guardfile(:guardfile_contents => valid_guardfile_string)
    end

    describe 'correctly throws errors when initializing with invalid data' do
      before { ::Guard::Dsl.stub!(:instance_eval_guardfile) }

      it 'raises error when there\'s a problem reading a file' do
        File.stub!(:exist?).with('/def/Guardfile') { true }
        File.stub!(:read).with('/def/Guardfile')   { raise Errno::EACCES.new('permission error') }

        Guard::UI.should_receive(:error).with(/^Error reading file/)
        lambda { described_class.evaluate_guardfile(:guardfile => '/def/Guardfile') }.should raise_error
      end

      it 'raises error when given Guardfile doesn\'t exist' do
        File.stub!(:exist?).with('/def/Guardfile') { false }

        Guard::UI.should_receive(:error).with(/No Guardfile exists at/)
        lambda { described_class.evaluate_guardfile(:guardfile => '/def/Guardfile') }.should raise_error
      end

      it 'raises error when resorting to use default, finds no default' do
        File.stub!(:exist?).with(local_guardfile) { false }
        File.stub!(:exist?).with(home_guardfile) { false }

        Guard::UI.should_receive(:error).with('No Guardfile found, please create one with `guard init`.')
        lambda { described_class.evaluate_guardfile }.should raise_error
      end

      it 'raises error when guardfile_content ends up empty or nil' do
        Guard::UI.should_receive(:error).with('No Guard plugins found in Guardfile, please add at least one.')
        described_class.evaluate_guardfile(:guardfile_contents => '')
      end

      it 'doesn\'t raise error when guardfile_content is nil (skipped)' do
        Guard::UI.should_not_receive(:error)
        lambda { described_class.evaluate_guardfile(:guardfile_contents => nil) }.should_not raise_error
      end
    end

    describe 'it should select the correct data source for Guardfile' do
      before { ::Guard::Dsl.stub!(:instance_eval_guardfile) }
      disable_user_config

      it 'should use a string for initializing' do
        Guard::UI.should_not_receive(:error)
        lambda { described_class.evaluate_guardfile(:guardfile_contents => valid_guardfile_string) }.should_not raise_error
        described_class.guardfile_contents.should eq valid_guardfile_string
      end

      it 'should use a given file over the default loc' do
        fake_guardfile('/abc/Guardfile', 'guard :foo')

        Guard::UI.should_not_receive(:error)
        lambda { described_class.evaluate_guardfile(:guardfile => '/abc/Guardfile') }.should_not raise_error
        described_class.guardfile_contents.should eq 'guard :foo'
      end

      it 'should use a default file if no other options are given' do
        fake_guardfile(local_guardfile, 'guard :bar')

        Guard::UI.should_not_receive(:error)
        lambda { described_class.evaluate_guardfile }.should_not raise_error
        described_class.guardfile_contents.should eq 'guard :bar'
      end

      it 'should use a string over any other method' do
        fake_guardfile('/abc/Guardfile', 'guard :foo')
        fake_guardfile(local_guardfile, 'guard :bar')

        Guard::UI.should_not_receive(:error)
        lambda { described_class.evaluate_guardfile(:guardfile_contents => valid_guardfile_string) }.should_not raise_error
        described_class.guardfile_contents.should eq valid_guardfile_string
      end

      it 'should use the given Guardfile over default Guardfile' do
        fake_guardfile('/abc/Guardfile', 'guard :foo')
        fake_guardfile(local_guardfile, 'guard :bar')

        Guard::UI.should_not_receive(:error)
        lambda { described_class.evaluate_guardfile(:guardfile => '/abc/Guardfile') }.should_not raise_error
        described_class.guardfile_contents.should eq 'guard :foo'
      end

      it 'should append the user config file if present' do
        fake_guardfile('/abc/Guardfile', 'guard :foo')
        fake_guardfile(home_config, 'guard :bar')
        Guard::UI.should_not_receive(:error)
        lambda { described_class.evaluate_guardfile(:guardfile => '/abc/Guardfile') }.should_not raise_error
        described_class.guardfile_contents.should eq "guard :foo\nguard :bar"
      end
    end

    describe 'correctly reads data from its valid data source' do
      before { ::Guard::Dsl.stub!(:instance_eval_guardfile) }
      disable_user_config

      it 'reads correctly from a string' do
        lambda { described_class.evaluate_guardfile(:guardfile_contents => valid_guardfile_string) }.should_not raise_error
        described_class.guardfile_contents.should eq valid_guardfile_string
      end

      it 'reads correctly from a Guardfile' do
        fake_guardfile('/abc/Guardfile', 'guard :foo')

        lambda { described_class.evaluate_guardfile(:guardfile => '/abc/Guardfile') }.should_not raise_error
        described_class.guardfile_contents.should eq 'guard :foo'
      end

      context 'with a local Guardfile only' do
        it 'reads correctly from it' do
          fake_guardfile(local_guardfile, valid_guardfile_string)

          lambda { described_class.evaluate_guardfile }.should_not raise_error
          described_class.guardfile_path.should eq local_guardfile
          described_class.guardfile_contents.should eq valid_guardfile_string
        end
      end

      context 'with a home Guardfile only' do
        it 'reads correctly from it' do
          File.stub!(:exist?).with(local_guardfile) { false }
          fake_guardfile(home_guardfile, valid_guardfile_string)

          lambda { described_class.evaluate_guardfile }.should_not raise_error
          described_class.guardfile_path.should eq home_guardfile
          described_class.guardfile_contents.should eq valid_guardfile_string
        end
      end

      context 'with both a local and a home Guardfile' do
        it 'reads correctly from the local Guardfile' do
          fake_guardfile(local_guardfile, valid_guardfile_string)
          fake_guardfile(home_guardfile, valid_guardfile_string)

          lambda { described_class.evaluate_guardfile }.should_not raise_error
          described_class.guardfile_path.should eq local_guardfile
          described_class.guardfile_contents.should eq valid_guardfile_string
        end
      end
    end
  end

  describe '.reevaluate_guardfile' do
    before do
      described_class.stub!(:instance_eval_guardfile)
      ::Guard.runner.stub(:run)
    end

    it 'evaluates the Guardfile' do
      described_class.should_receive(:evaluate_guardfile)
      described_class.reevaluate_guardfile
    end

    it 'stops all Guards' do
      ::Guard.runner.should_receive(:run).with(:stop)

      described_class.reevaluate_guardfile
    end

    it 'reset all Guard plugins' do
      ::Guard.should_receive(:reset_guards)

      described_class.reevaluate_guardfile
    end

    it 'resets all groups' do
      ::Guard.should_receive(:reset_groups)

      described_class.reevaluate_guardfile
    end

    it 'clears the notifications' do
       ::Guard::Notifier.turn_off
       ::Guard::Notifier.notifications = [{ :name => :growl }]
       ::Guard::Notifier.notifications.should_not be_empty

       described_class.reevaluate_guardfile

       ::Guard::Notifier.notifications.should eq []
    end

    it 'removes the cached Guardfile content' do
      described_class.reevaluate_guardfile

      described_class.options.should_not have_key(:guardfile_content)
    end

    context 'with notifications enabled' do
      before { ::Guard::Notifier.stub(:enabled?).and_return true }

      it 'enables the notifications again' do
        ::Guard::Notifier.should_receive(:turn_on)
        described_class.reevaluate_guardfile
      end
    end

    context 'with notifications disabled' do
      before { ::Guard::Notifier.stub(:enabled?).and_return false }

      it 'does not enable the notifications again' do
        ::Guard::Notifier.should_not_receive(:turn_on)
        described_class.reevaluate_guardfile
      end
    end

    context 'with Guards afterwards' do
      it 'shows a success message' do
        ::Guard.runner.stub(:run)

        ::Guard::UI.should_receive(:info).with('Guardfile has been re-evaluated.')
        described_class.reevaluate_guardfile
      end

      it 'shows a success notification' do
        ::Guard::Notifier.should_receive(:notify).with('Guardfile has been re-evaluated.', :title => 'Guard re-evaluate')
        described_class.reevaluate_guardfile
      end

      it 'starts all Guards' do
        ::Guard.runner.should_receive(:run).with(:start)

        described_class.reevaluate_guardfile
      end
    end

    context 'without Guards afterwards' do
      before { ::Guard.stub(:guards).and_return([]) }

      it 'shows a failure notification' do
        ::Guard::Notifier.should_receive(:notify).with('No guards found in Guardfile, please add at least one.', :title => 'Guard re-evaluate', :image => :failed)
        described_class.reevaluate_guardfile
      end
    end
  end

  describe '.guardfile_include?' do
    it 'detects a guard specified by a string with double quotes' do
      described_class.stub(:guardfile_contents_without_user_config => 'guard "test" {watch("c")}')

      described_class.guardfile_include?('test').should be_true
    end

    it 'detects a guard specified by a string with single quote' do
      described_class.stub(:guardfile_contents_without_user_config => 'guard \'test\' {watch("c")}')

      described_class.guardfile_include?('test').should be_true
    end

    it 'detects a guard specified by a symbol' do
      described_class.stub(:guardfile_contents_without_user_config => 'guard :test {watch("c")}')

      described_class.guardfile_include?('test').should be_true
    end

    it 'detects a guard wrapped in parentheses' do
      described_class.stub(:guardfile_contents_without_user_config => 'guard(:test) {watch("c")}')

      described_class.guardfile_include?('test').should be_true
    end
  end

  describe '#ignore_paths' do
    disable_user_config

    it 'adds the paths to the listener\'s ignore_paths' do
      ::Guard::UI.should_receive(:deprecation).with(Guard::Deprecator::DSL_METHOD_IGNORE_PATHS_DEPRECATION)

      described_class.evaluate_guardfile(:guardfile_contents => 'ignore_paths \'foo\', \'bar\'')
    end
  end

  describe '#ignore' do
    disable_user_config
    let(:listener) { stub }

    it 'add ignored regexps to the listener' do
      ::Guard.stub(:listener) { listener }
      ::Guard.listener.should_receive(:ignore).with(/^foo/,/bar/) { listener }
      ::Guard.should_receive(:listener=).with(listener)

      described_class.evaluate_guardfile(:guardfile_contents => 'ignore %r{^foo}, /bar/')
    end
  end

  describe '#ignore!' do
    disable_user_config
    let(:listener) { stub }

    it 'replace ignored regexps in the listener' do
      ::Guard.stub(:listener) { listener }
      ::Guard.listener.should_receive(:ignore!).with(/^foo/,/bar/) { listener }
      ::Guard.should_receive(:listener=).with(listener)

      described_class.evaluate_guardfile(:guardfile_contents => 'ignore! %r{^foo}, /bar/')
    end
  end

  describe '#filter' do
    disable_user_config
    let(:listener) { stub }

    it 'add ignored regexps to the listener' do
      ::Guard.stub(:listener) { listener }
      ::Guard.listener.should_receive(:filter).with(/.txt$/, /.*.zip/) { listener }
      ::Guard.should_receive(:listener=).with(listener)

      described_class.evaluate_guardfile(:guardfile_contents => 'filter %r{.txt$}, /.*.zip/')
    end
  end

  describe '#filter!' do
    disable_user_config
    let(:listener) { stub }

    it 'replace ignored regexps in the listener' do
      ::Guard.stub(:listener) { listener }
      ::Guard.listener.should_receive(:filter!).with(/.txt$/, /.*.zip/) { listener }
      ::Guard.should_receive(:listener=).with(listener)

      described_class.evaluate_guardfile(:guardfile_contents => 'filter! %r{.txt$}, /.*.zip/')
    end
  end

  describe '#notification' do
    disable_user_config

    it 'adds a notification to the notifier' do
      ::Guard::Notifier.should_receive(:add_notification).with(:growl, {}, false)
      described_class.evaluate_guardfile(:guardfile_contents => 'notification :growl')
    end

    it 'adds multiple notification to the notifier' do
      ::Guard::Notifier.should_receive(:add_notification).with(:growl, {}, false)
      ::Guard::Notifier.should_receive(:add_notification).with(:ruby_gntp, { :host => '192.168.1.5' }, false)
      described_class.evaluate_guardfile(:guardfile_contents => "notification :growl\nnotification :ruby_gntp, :host => '192.168.1.5'")
    end
  end

  describe '#interactor' do
    disable_user_config

    it 'disables the interactions with :off' do
      ::Guard::UI.should_not_receive(:deprecation).with(Guard::Deprecator::DSL_METHOD_INTERACTOR_DEPRECATION)
      described_class.evaluate_guardfile(:guardfile_contents => 'interactor :off')
      Guard::Interactor.enabled.should be_false
    end

    it 'shows a deprecation for symbols other than :off' do
      ::Guard::UI.should_receive(:deprecation).with(Guard::Deprecator::DSL_METHOD_INTERACTOR_DEPRECATION)
      described_class.evaluate_guardfile(:guardfile_contents => 'interactor :coolline')
    end

    it 'passes the options to the interactor' do
      ::Guard::UI.should_not_receive(:deprecation).with(Guard::Deprecator::DSL_METHOD_INTERACTOR_DEPRECATION)
      described_class.evaluate_guardfile(:guardfile_contents => 'interactor :option1 => \'a\', :option2 => 123')
      Guard::Interactor.options.should include({ :option1 => 'a', :option2 => 123 })
    end
  end

  describe '#group' do
    disable_user_config

    context 'no plugins in group' do
      it 'displays an error' do
        ::Guard::UI.should_receive(:error).with("No Guard plugins found in the group 'w', please add at least one.")

        described_class.evaluate_guardfile(:guardfile_contents => guardfile_string_with_empty_group)
      end
    end

    it 'evaluates all groups' do
      ::Guard.should_receive(:add_guard).with(:pow,   { :watchers => [], :callbacks => [], :group => :default })
      ::Guard.should_receive(:add_guard).with(:test,  { :watchers => [], :callbacks => [], :group => :w })
      ::Guard.should_receive(:add_guard).with(:rspec, { :watchers => [], :callbacks => [], :group => :x })
      ::Guard.should_receive(:add_guard).with(:ronn,  { :watchers => [], :callbacks => [], :group => :x })
      ::Guard.should_receive(:add_guard).with(:less,  { :watchers => [], :callbacks => [], :group => :y })

      described_class.evaluate_guardfile(:guardfile_contents => valid_guardfile_string)
    end
  end

  describe '#guard' do
    disable_user_config

    it 'loads a guard specified as a quoted string from the DSL' do
      ::Guard.should_receive(:add_guard).with('test', { :watchers => [], :callbacks => [], :group => :default })

      described_class.evaluate_guardfile(:guardfile_contents => 'guard \'test\'')
    end

    it 'loads a guard specified as a double quoted string from the DSL' do
      ::Guard.should_receive(:add_guard).with('test', { :watchers => [], :callbacks => [], :group => :default })

      described_class.evaluate_guardfile(:guardfile_contents => 'guard "test"')
    end

    it 'loads a guard specified as a symbol from the DSL' do
      ::Guard.should_receive(:add_guard).with(:test, { :watchers => [], :callbacks => [], :group => :default })

      described_class.evaluate_guardfile(:guardfile_contents => 'guard :test')
    end

    it 'loads a guard specified as a symbol and called with parens from the DSL' do
      ::Guard.should_receive(:add_guard).with(:test, { :watchers => [], :callbacks => [], :group => :default })

      described_class.evaluate_guardfile(:guardfile_contents => 'guard(:test)')
    end

    it 'receives options when specified, from normal arg' do
      ::Guard.should_receive(:add_guard).with('test', { :watchers => [], :callbacks => [], :opt_a => 1, :opt_b => 'fancy', :group => :default })

      described_class.evaluate_guardfile(:guardfile_contents => 'guard \'test\', :opt_a => 1, :opt_b => \'fancy\'')
    end
  end

  describe '#watch' do
    disable_user_config

    it 'should receive watchers when specified' do
      ::Guard.should_receive(:add_guard).with(:dummy, { :watchers => [anything, anything], :callbacks => [], :group => :default }) do |_, options|
        options[:watchers].size.should eq 2
        options[:watchers][0].pattern.should eq 'a'
        options[:watchers][0].action.call.should eq proc { 'b' }.call
        options[:watchers][1].pattern.should eq 'c'
        options[:watchers][1].action.should be_nil
      end
      described_class.evaluate_guardfile(:guardfile_contents => '
      guard :dummy do
         watch(\'a\') { \'b\' }
         watch(\'c\')
      end')
    end
  end

  describe '#callback' do
    it 'creates callbacks for the guard' do
      class MyCustomCallback
        def self.call(guard_class, event, args)
          # do nothing
        end
      end

      ::Guard.should_receive(:add_guard).with(:dummy, { :watchers => [], :callbacks => [anything, anything], :group => :default }) do |_, options|
        options[:callbacks].should have(2).items
        options[:callbacks][0][:events].should    eq :start_end
        options[:callbacks][0][:listener].call(Guard::Dummy, :start_end, 'foo').should eq 'Guard::Dummy executed \'start_end\' hook with foo!'
        options[:callbacks][1][:events].should eq [:start_begin, :run_all_begin]
        options[:callbacks][1][:listener].should eq MyCustomCallback
      end
      described_class.evaluate_guardfile(:guardfile_contents => '
        guard :dummy do
          callback(:start_end) { |guard_class, event, args| "#{guard_class} executed \'#{event}\' hook with #{args}!" }
          callback(MyCustomCallback, [:start_begin, :run_all_begin])
        end')
    end
  end

  describe '#logger' do
    after { Guard::UI.options = { :level => :info, :template => ':time - :severity - :message', :time_format => '%H:%M:%S' } }

    context 'with valid options' do
      it 'sets the logger log level' do
        described_class.evaluate_guardfile(:guardfile_contents => 'logger :level => :error')
        Guard::UI.options[:level].should eq :error
      end

      it 'sets the logger log level and convert to a symbol' do
        described_class.evaluate_guardfile(:guardfile_contents => 'logger :level => \'error\'')
        Guard::UI.options[:level].should eq :error
      end

      it 'sets the logger template' do
        described_class.evaluate_guardfile(:guardfile_contents => 'logger :template => \':message - :severity\'')
        Guard::UI.options[:template].should eq ':message - :severity'
      end

      it 'sets the logger time format' do
        described_class.evaluate_guardfile(:guardfile_contents => 'logger :time_format => \'%Y\'')
        Guard::UI.options[:time_format].should eq '%Y'
      end

      it 'sets the logger only filter from a symbol' do
        described_class.evaluate_guardfile(:guardfile_contents => 'logger :only => :cucumber')
        Guard::UI.options[:only].should eq(/cucumber/i)
      end

      it 'sets the logger only filter from a string' do
        described_class.evaluate_guardfile(:guardfile_contents => 'logger :only => \'jasmine\'')
        Guard::UI.options[:only].should eq(/jasmine/i)
      end

      it 'sets the logger only filter from an array of symbols and string' do
        described_class.evaluate_guardfile(:guardfile_contents => 'logger :only => [:rspec, \'cucumber\']')
        Guard::UI.options[:only].should eq(/rspec|cucumber/i)
      end

      it 'sets the logger except filter from a symbol' do
        described_class.evaluate_guardfile(:guardfile_contents => 'logger :except => :jasmine')
        Guard::UI.options[:except].should eq(/jasmine/i)
      end

      it 'sets the logger except filter from a string' do
        described_class.evaluate_guardfile(:guardfile_contents => 'logger :except => \'jasmine\'')
        Guard::UI.options[:except].should eq(/jasmine/i)
      end

      it 'sets the logger except filter from an array of symbols and string' do
        described_class.evaluate_guardfile(:guardfile_contents => 'logger :except => [:rspec, \'cucumber\', :jasmine]')
        Guard::UI.options[:except].should eq(/rspec|cucumber|jasmine/i)
      end
    end

    context 'with invalid options' do
      context 'for the log level' do
        it 'shows a warning' do
          Guard::UI.should_receive(:warning).with 'Invalid log level `baz` ignored. Please use either :debug, :info, :warn or :error.'
          described_class.evaluate_guardfile(:guardfile_contents => 'logger :level => :baz')
        end

        it 'does not set the invalid value' do
          described_class.evaluate_guardfile(:guardfile_contents => 'logger :level => :baz')
          Guard::UI.options[:level].should eq :info
        end
      end

      context 'when having both the :only and :except options' do
        it 'shows a warning' do
          Guard::UI.should_receive(:warning).with 'You cannot specify the logger options :only and :except at the same time.'
          described_class.evaluate_guardfile(:guardfile_contents => 'logger :only => :jasmine, :except => :rspec')
        end

        it 'removes the options' do
          described_class.evaluate_guardfile(:guardfile_contents => 'logger :only => :jasmine, :except => :rspec')
          Guard::UI.options[:only].should be_nil
          Guard::UI.options[:except].should be_nil
        end
      end

    end
  end

  describe '#scope' do
    context 'with an existing command line plugin scope' do
      before do
        ::Guard.options[:plugin] = ['rspec']
        ::Guard.options[:group] = []
      end

      it 'does not use the DSL scope plugin' do
        described_class.evaluate_guardfile(:guardfile_contents => 'scope :plugin => :baz')
        ::Guard.options[:plugin].should eq ['rspec']
      end

      it 'does not use the DSL scope plugins' do
        described_class.evaluate_guardfile(:guardfile_contents => 'scope :plugins => [:foo, :bar]')
        ::Guard.options[:plugin].should eq ['rspec']
      end
    end

    context 'without an existing command line plugin scope' do
      before do
        ::Guard.options[:plugin] = []
        ::Guard.options[:group] = []
      end

      it 'does use the DSL scope plugin' do
        described_class.evaluate_guardfile(:guardfile_contents => 'scope :plugin => :baz')
        ::Guard.options[:plugin].should eq [:baz]
      end

      it 'does use the DSL scope plugins' do
        described_class.evaluate_guardfile(:guardfile_contents => 'scope :plugins => [:foo, :bar]')
        ::Guard.options[:plugin].should eq [:foo, :bar]
      end
    end

    context 'with an existing command line group scope' do
      before do
        ::Guard.options[:plugin] = []
        ::Guard.options[:group] = ['frontend']
      end

      it 'does not use the DSL scope plugin' do
        described_class.evaluate_guardfile(:guardfile_contents => 'scope :group => :baz')
        ::Guard.options[:group].should eq ['frontend']
      end

      it 'does not use the DSL scope plugins' do
        described_class.evaluate_guardfile(:guardfile_contents => 'scope :groups => [:foo, :bar]')
        ::Guard.options[:group].should eq ['frontend']
      end
    end

    context 'without an existing command line group scope' do
      before do
        ::Guard.options[:plugin] = []
        ::Guard.options[:group] = []
      end

      it 'does use the DSL scope group' do
        described_class.evaluate_guardfile(:guardfile_contents => 'scope :group => :baz')
        ::Guard.options[:group].should eq [:baz]
      end

      it 'does use the DSL scope groups' do
        described_class.evaluate_guardfile(:guardfile_contents => 'scope :groups => [:foo, :bar]')
        ::Guard.options[:group].should eq [:foo, :bar]
      end
    end
  end

  private

  def fake_guardfile(name, contents)
    File.stub!(:exist?).with(name) { true }
    File.stub!(:read).with(name)   { contents }
  end

  def valid_guardfile_string
    '
    notification :growl

    guard :pow

    group :w do
      guard :test
    end

    group :x, :halt_on_fail => true do
      guard :rspec
      guard :ronn
    end

    group :y do
      guard :less
    end
    '
  end

  def guardfile_string_with_empty_group
    'group :w'
  end

  def invalid_guardfile_string
    'Bad Guardfile'
  end
end
