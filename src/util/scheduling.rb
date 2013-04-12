require 'rufus/scheduler'

module Scheduling
  def scheduler
    Scheduling.scheduler
  end

  def self.scheduler
    @scheduler ||= Rufus::Scheduler.start_new
  end
end
