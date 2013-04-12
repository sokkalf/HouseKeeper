class Proc
  # redefine Proc to include name field
  # (used for logging what type of task is scheduled)
  attr_accessor :name
end