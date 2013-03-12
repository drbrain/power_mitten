module ATT # :nodoc:
end

module ATT::CloudGauntlet

  VERSION = '1.0'

end

require 'att/cloud_gauntlet/configuration'
require 'att/cloud_gauntlet/fog_utilities'
require 'att/cloud_gauntlet/node'
require 'att/cloud_gauntlet/checksum_dump'
require 'att/cloud_gauntlet/collect'
require 'att/cloud_gauntlet/console'
require 'att/cloud_gauntlet/control'
require 'att/cloud_gauntlet/gem_checksummer'
require 'att/cloud_gauntlet/gem_dependencies'
require 'att/cloud_gauntlet/gem_downloader'
require 'att/cloud_gauntlet/irb'
require 'att/cloud_gauntlet/rdocer'
require 'att/cloud_gauntlet/ring_server'
require 'att/cloud_gauntlet/startup'

