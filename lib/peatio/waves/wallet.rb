# frozen_string_literal: true

module Peatio
  module Waves
    class Wallet < Peatio::Wallet::Abstract

      DEFAULT_FEE = { gas_limit: 21_000, gas_price: 1_000_00 }.freeze

      def initialize(settings = {})
        @settings = settings
        configure
      end

      def configure(settings = {})
        # Clean client state during configure.
        @client = nil

        @settings.merge!(settings.slice(*SUPPORTED_SETTINGS))

        @wallet = @settings.fetch(:wallet) do
          raise Peatio::Wallet::MissingSettingError, :wallet
        end.slice(:uri, :address, :secret)

        @currency = @settings.fetch(:currency) do
          raise Peatio::Wallet::MissingSettingError, :currency
        end.slice(:id, :base_factor, :options)
      end

      def create_address!(_options = {})
        {
            address: client.client(:post, "addresses").fetch('address'),
        }
      rescue Waves::Client::Error => e
        raise Peatio::Wallet::ClientError, e
      end

      def create_transaction!(transaction, options = {})
        create_waves_token_transaction!(transaction, options)
      rescue Waves::Client::Error => e
        raise Peatio::Wallet::ClientError, e
      end

      def load_balance!
        if @currency.dig(:options, :erc20_contract_address).present?
          load_waves_token_balance(@wallet.fetch(:address))
        else
          address_with_balance = client.client(:get, "addresses/balance/#{@wallet.fetch(:address)}")
          address_with_balance.fetch('balance').to_d
              .yield_self { |amount| convert_from_base_unit(amount) }
        end
      rescue Waves::Client::Error => e
        raise Peatio::Wallet::ClientError, e
      end

      def transaction_fee(transaction)
        address_with_balance = client.client(:post, "/transactions/calculateFee", transaction)
        address_with_balance.fetch('balance').to_d
            .yield_self { |amount| convert_from_base_unit(amount) }
      end

      def prepare_deposit_collection!(transaction, deposit_spread, deposit_currency)
        puts deposit_currency
        puts deposit_currency.dig(:options, :erc20_contract_address).blank?

        # TODO: Add spec for this behaviour.
        # Don't prepare for deposit_collection in case of eth deposit.
        return [] if deposit_currency.dig(:options, :erc20_contract_address).blank?

        options = deposit_currency.fetch(:options).slice(:gas_limit, :gas_price, :erc20_contract_address)
        options = options.merge(DEFAULT_FEE)
        options = options.merge({collection: true})
        puts options
        # We collect fees depending on the number of spread deposit size
        # Example: if deposit spreads on three wallets need to collect eth fee for 3 transactions
        fees = convert_from_base_unit(options.fetch(:gas_price).to_i)
        transaction.amount = fees

        [create_waves_token_transaction!(transaction, options)]
      rescue Waves::Client::Error => e
        raise Peatio::Wallet::ClientError, e
      end

      private

      def load_waves_token_balance(address)
        address_with_balance = client.client(:get, "assets/balance/#{address}/#{contract_address}")
        address_with_balance.fetch('balance').to_d
            .yield_self { |amount| convert_from_base_unit(amount) }
      end

      def create_waves_token_transaction!(transaction, options = {})
        currency_options = @currency.fetch(:options).slice(:gas_limit, :gas_price, :erc20_contract_address)
        options = options.merge!(currency_options)
        options = options.merge!(DEFAULT_FEE)
        txid = client.client(:post, "transactions/broadcast", build_transaction(transaction, options).to_json)

        transaction.hash = normalize_txid(txid.fetch('id'))
        transaction
      end

      def build_transaction(transaction, options)
        address = normalize_address(@wallet.fetch(:address))
        asset_id = options.fetch(:erc20_contract_address)

        amount = convert_to_base_unit(transaction.amount)

        # Subtract fees from initial deposit amount in case of deposit collection
        amount -= options.fetch(:gas_price).to_i if options.dig(:subtract_fee) && asset_id.blank?

        tx = {
            type: 4,
            version: 2,
            sender: address,
            recipient: normalize_address(transaction.to_address),
            amount: amount,
            fee: options.fetch(:gas_price),
        }
        tx = tx.merge({assetId: asset_id}) if !asset_id.blank? && !options.dig(:collection)
        client.client(:post, "transactions/sign", tx.to_json)
      end

      def timestamp
        @timestamp ||= Time.now.to_i * 1000
      end

      def normalize_address(address)
        address
      end

      def normalize_asset_id(address = nil)
        return if address.nil?
        address === 'WAVES' ? nil : normalize_address(address)
      end

      def normalize_txid(txid)
        txid
      end

      def contract_address
        normalize_address(@currency.dig(:options, :erc20_contract_address))
      end

      def convert_from_base_unit(value)
        value.to_d / @currency.fetch(:base_factor)
      end

      def convert_to_base_unit(value)
        x = value.to_d * @currency.fetch(:base_factor)
        unless (x % 1).zero?
          raise Peatio::WalletClient::Error,
                "Failed to convert value to base (smallest) unit because it exceeds the maximum precision: " \
            "#{value.to_d} - #{x.to_d} must be equal to zero."
        end
        x.to_i
      end

      def client
        uri = @wallet.fetch(:uri) { raise Peatio::Wallet::MissingSettingError, :uri }
        @client ||= Client.new(uri)
      end
    end
  end
end
