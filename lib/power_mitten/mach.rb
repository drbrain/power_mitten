require 'fiddle'
require 'fiddle/import'

##
# This assumes 64 bit OS X and imports magic numbers directly.
#
# For some further explanation, see:
# http://miknight.blogspot.com/2005/11/resident-set-size-in-mac-os-x.html

module PowerMitten::Mach

  extend Fiddle::Importer
  dlload '/usr/lib/libSystem.dylib'

  MACH_BASIC_TASK_INFO = 5
  MACH_BASIC_TASK_INFO_COUNT = 10

  @current_task = import_symbol('mach_task_self_').ptr.to_i

  @task_for_pid =
    extern 'int task_for_pid(unsigned int, int, void *)'
  @task_info    =
    extern 'void task_info(void *, int, long *, unsigned long *)'

  @task = nil

  ##
  # Returns the Resident Set Size in kilobytes for the current process

  def self.resident_set_size
    @task ||=
      begin
        task = Fiddle::Pointer.malloc Fiddle::SIZEOF_INT
        task[0] = 0
        return nil unless 0 == @task_for_pid.call(@current_task, $$, task)
        task
      end

    task_info_count = Fiddle::Pointer.malloc Fiddle::SIZEOF_LONG
    task_info_count[0] = MACH_BASIC_TASK_INFO_COUNT
    task_info = Fiddle::Pointer.malloc 40

    @task_info.call @task.ptr, MACH_BASIC_TASK_INFO, task_info, task_info_count

    task_info.to_str.unpack('LQQ').last
  end

end

