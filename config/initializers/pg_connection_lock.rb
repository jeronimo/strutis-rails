# TEMPORARY: delete when Rails releases rails/rails#57517 (connection_lock option)
# and set `connection_lock: monitor` in database.yml instead.
#
# The pg adapter runs with NullLock, so a reconnect (fork-inherited connection,
# retry path) races with concurrent queries and leaves @type_map/@type_map_for_results
# nil mid-query (rails/rails#51780). A real Monitor serializes adapter use, which is
# what upstream's fix does with a config flag. Monitor is reentrant, so nested
# synchronize calls inside with_raw_connection are safe.
require 'monitor'

ActiveSupport.on_load(:active_record_postgresqladapter) do
  prepend(Module.new do
    def initialize(...)
      super
      @lock = Monitor.new
    end
  end)
end
