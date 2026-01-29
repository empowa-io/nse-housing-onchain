use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Address}
use cardano/assets.{AssetName, PolicyId}

pub type OrderType {
  Buy
  Sell
}

pub type OrderDatum {
  order_type: OrderType,
  traded_asset_policy_id: PolicyId,
  traded_asset_name: AssetName,
  traded_asset_amount: Int,
  traded_asset_price: Int,
  partial_fulfillment_allowed: Bool,
  order_timeout_date: Int,
  order_maker_address: Address,
}

pub type ConfigDatum {
  platform_fee_percent: Int,
  platform_fee_decimal: Int,
  platform_fee_min_amount: Int,
  platform_fee_address: Address,
  contract_operator_keyhash: VerificationKeyHash,
  listing_operator_keyhash: VerificationKeyHash,
  is_market_open: Bool,
}

pub type ListingDatum {
  listed_policy_id: PolicyId,
  listed_asset_name: Option<AssetName>,
}

pub type ContractMode {
  Bootstrap
  Configuration
  Listing
  Delisting
  Cleaning
  OrderPlacing
  OrderChanging
  OrderCanceling
  OrderExecution
}

pub type OutputRefOrPolicyId =
  Data

pub type Marker {
  Marker(PolicyId, AssetName)
}
