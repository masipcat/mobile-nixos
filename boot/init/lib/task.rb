# Namespace where tasks can be defined, and hosting methods harmonizing a run.
module Tasks
  # Register a singleton task to be instantiated and ran.
  # @internal
  def self.register_singleton(klass)
    $logger.debug("Task #{klass.name} registered...")
    @singletons_to_be_instantiated ||= []
    @singletons_to_be_instantiated << klass
  end

  # Register one task to be ran.
  def self.register(task)
    $logger.debug("Task #{task.name} registered...")
    @tasks ||= []
    @tasks << task
  end

  # Tries to run *all* tasks.
  def self.go()
    # Registers tasks that still needs to be instantiated
    @singletons_to_be_instantiated.each do |klass|
      # Their mere existence registers them.
      klass.instance
    end
    @singletons_to_be_instantiated = []

    # Sort tasks to reduce the amount of loops it needs to fulfill them all.
    # It's only a reduction due to files, mounts and devices being
    # unpredictable!
    @tasks.sort!

    until @tasks.all?(&:ran) do
      $logger.debug("Tasks resolution loop start")
      @tasks
        .reject(&:ran)
        .each do |task|
          task._try_run_task
        end
      # Don't burn the CPU
      sleep(0.1)
    end
  end
end

# Basic task class.
class Task
  attr_reader :ran

  def self.new(*args)
    $logger.debug("New instance of #{self.name}...")
    $logger.debug(" -> #{args.inspect}")
    instance = super(*args)
    Tasks.register(instance)
    instance
  end

  def name
    self.class.name
  end

  def self.inherited(subclass)
    $logger.debug("#{subclass.name} created...")
  end

  # Sort first by dependencies, then by name, then by object_id
  # (for stable sort order)
  def <=>(other)
    return -1 if other.depends_on?(self)
    return  1 if depends_on?(other)

    by_ux_priority = ux_priority <=> other.ux_priority
    return by_ux_priority unless by_ux_priority == 0 

    by_name = name <=> other.name
    return by_name unless by_name == 0

    object_id <=> other.object_id
  end

  def depends_on?(other)
    dependencies.any? do |dependency|
      dependency.depends_on?(other)
    end
  end

  def add_dependency(kind, *args)
    raise NameError.new("No dependency named #{kind}") unless Dependencies.constants.include?(kind.to_sym)
    dependencies << Dependencies.const_get(kind.to_sym).new(*args)
  end

  def dependencies_fulfilled?()
    dependencies.all?(&:fulfilled?)
  end

  # Internal actual way to run the task
  # This runs the `#run` method.
  def _try_run_task()
    $logger.debug("Looking to run task #{name}...")
    return unless dependencies_fulfilled?
    unless @ran
      $logger.info("Running #{name}...")
      run()
      $logger.debug("Finished #{name}...")
      @ran = true
    end
  end

  def dependencies()
    @dependencies ||= []
    @dependencies
  end

  # This allows a task to be ordered before other tasks, because it is used to
  # enhance the UX of the boot process. Assume this will be compared with +<=>+.
  # This should seldom be used, and mainly for tasks that show the progress of
  # the boot process.
  # (For internal use.)
  # @internal
  def ux_priority()
    0
  end
end

# A task that can only have one instance.
class SingletonTask < Task
  include Singleton

  def self.inherited(subclass)
    super
    # Delay initializing, as right now we have an fresh new empty class.
    Tasks.register_singleton(subclass)
  end
end
