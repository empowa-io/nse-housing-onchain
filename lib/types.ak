use aiken/crypto.{Signature, VerificationKey, VerificationKeyHash}
use cardano/assets.{AssetName, PolicyId}

pub type OrderType {
  Buy
  Sell
}

pub type ContractDatum {
  OrderDatum {
    order_type: OrderType,
    traded_asset_policy_id: PolicyId,
    traded_asset_name: AssetName,
    traded_asset_amount: Int,
    traded_asset_price: Int,
    partial_fulfillment_allowed: Bool,
    order_timeout_date: Int,
    order_maker_credential: VerificationKeyHash,
  }
  ConfigDatum {
    fee_size: Int,
    contract_operator_credential: VerificationKeyHash,
    listing_verification_key: VerificationKey,
    is_market_open: Bool,
  }
}

pub type ListingDatum {
  listed_policy_id: PolicyId,
  listed_asset_name: Option<AssetName>,
  listing_signature: Signature,
}

pub type ContractMode {
  Bootstrap
  Configuration
  Cleaning
  OrderPlacing
  OrderChanging
  OrderCanceling
  OrderExecution
}
