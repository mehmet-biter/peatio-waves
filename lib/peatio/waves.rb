require "active_support/core_ext/object/blank"
require "active_support/core_ext/enumerable"
require "peatio"
require "bip_mnemonic"

module Peatio
  module Waves
    require "waves_client"
    require "bigdecimal"
    require "bigdecimal/util"
    require "peatio/waves/blockchain"
    require "peatio/waves/client"
    require "peatio/waves/wallet"
    require "peatio/waves/hooks"
    require "peatio/waves/version"
  end
end
