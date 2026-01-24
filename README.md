# **NSE Housing Contract**

### *(On-chain component, Cardano)*

This smart contract implements a mechanism for buying and selling tokens on the **Cardano** blockchain.

---

## **Roles and Capabilities**

### **Contract Operator**

The operator has the following privileges:

* **Contract configuration management**

  * Set and update contract parameters
  * Transfer contract control to another operator
* **Forced order cancellation**

  * With asset return to the order owner
  * For example, if a token is delisted and waiting for a timeout is pointless
* **Garbage UTXO cleanup**

  * UTXOs created without the contract's participation

---

### **Listing Operator**

* **Token listing and delisting**

  * By `policy_id`
  * By `policy_id + asset_name`

> Note: `listing_operator_credential` may match `contract_operator_keyhash` if role separation is not required.

---

### **Order Initiator (Order Creator)**

* **Create a configurable order**

  * Buy order (locks ADA)
  * Sell order (locks an asset)
* **Modify order parameters**
* **Early order cancellation**

  * If timeout changes are allowed, early cancellation is allowed as well

---

### **Order Acceptor**

* **Accepting order terms**

  * Initiates a deal under the conditions defined in the order

---

### **Any User (Outside Explicit Roles)**

* **Cancellation of orders with expired timeout**

  * No authentication required
  * Only requires a correctly constructed transaction
* In practice, this will most likely be handled by the platform backend

---

## **Contract Structure**

### **1. Configuration eUTXO**

Stores global contract parameters.

#### **Datum**

* `platform_fee_percent` (0..10000, meaning 0.00%..100.00%)
* `platform_fee_decimal` (decimal precision for fee percent)
* `platform_fee_min_amount` (minimum fee in lovelace)
* `platform_fee_address`
* `contract_operator_keyhash`
* `listing_operator_credential`
* `is_market_open`

#### **Assets**

Contract-issued asset **CONF** (`contract_config_marker`, 1 unit)

#### **Rules**

* The **CONF** token may exist in **only one instance** and can not be minted

  * Exception: bootstrap phase
* If `is_market_open` is `False`, the contract only accepts transactions authorized by the operator
* A UTXO containing CONF may be moved only if all conditions are met:

  1. The output is sent only to the current contract address
  2. The new UTXO contains a Datum with valid parameters
  3. The transaction is signed by the active operator (extra signature)
  4. If the operator is changed, an extra signature from the **new operator** is required
     *(to validate credentials and prevent loss of control)*

---

### **2. Listing eUTXOs**

* One eUTXO per asset (or per policy with wildcard)
* May exist **only at the contract address**

#### **Datum**

* `listed_policy_id`
* `Option<listed_asset_name>`
  * `None` means all asset names under the given policy are allowed

#### **Rules**

* Listing is performed by minting `contract_listing_marker` and creating contract outputs with `ListingDatum`
* Delisting is performed by spending listing inputs and **burning** the same number of markers
* Listing and delisting require a reference to the config eUTxO and a signature by `listing_operator_credential`

---

### **3. Order eUTXOs**

* One eUTXO per order
* Must exist **only at the contract address**

#### **Creation Requirements**

1. Minting of the **ORDER** token by the contract

   * Exactly **1 unit**
2. Reference to a valid asset listing
3. Reference to a valid contract configuration
4. Datum with the following structure:

   * Order type: buy / sell

     * Sell → user locks asset
     * Buy → user locks ADA
   * `policy_id` of the traded asset
   * `asset_name` of the traded asset
   * Asset amount (base units, without decimal divider)
   * Asset price (base units, without decimal divider)
   * Partial fulfillment allowed (yes/no)
   * `timeout`
   * `order_maker_keyhash`
5. Order output placed at the contract address

---

## **Static Contract Parameters**

* **Bootstrap UTXO**

  * Allows initial minting of CONF and creation of the configuration eUTXO
  * Due to UTXO single-use semantics, guarantees that CONF cannot be duplicated
  * Defined by `contract_bootstrap_utxo_hash` + `contract_bootstrap_utxo_index`
* **Contract markers**

  * `contract_config_marker` (CONF)
  * `contract_order_marker` (ORDER)
  * `contract_listing_marker` (LISTING)
* **Order placement deposit**

  * Amount of ADA attached to an order
  * Returned to the order owner
  * Required for:

    * Existence of the ORDER token
    * Covering fees for automatic timeout-based order cancellation
  * Defined by `contract_order_min_ada`

---

## **Contract Operation Modes**

### **1. Bootstrap**

Initial contract setup.

* Uses the `Bootstrap UTXO`
* Can be executed **only once**
* Mandatory:

  * Exactly one input equal to `contract_bootstrap_utxo_hash#contract_bootstrap_utxo_index`
  * Exactly one output to the contract address (index 0) with `contract_config_marker` and a valid `ConfigDatum`
  * Any number of outputs to other addresses if needed (not validated)
  * Minting exactly one `contract_config_marker`
  * Operator signature (`contract_operator_keyhash`)

---

### **2. Configuration**

Changing contract parameters.

* Mandatory:

  * Exactly one input containing `contract_config_marker`
  * Exactly one output to the contract address (index 0) with `contract_config_marker` and a valid `ConfigDatum`
  * Any number of outputs to other addresses if needed (not validated)
  * Minting is **forbidden**
  * Operator signature from the **current** config
  * Operator signature from the **new** config if the operator changes

---

### **3. Listing**

Creating listing eUTXOs.

* Mandatory:

  * Reference to the valid `config eUTxO`
  * One or more outputs to the contract address with:

    * 1 token `contract_listing_marker` per output
    * a valid `ListingDatum`
  * Any number of outputs to other addresses if needed (not validated)
  * Minting exactly one `contract_listing_marker` per listing output
  * Signature of `listing_operator_credential`

---

### **4. Delisting**

Removing listing eUTXOs.

* Mandatory:

  * Reference to the valid `config eUTxO`
  * One or more inputs from the contract address, each containing `contract_listing_marker`
  * No outputs containing `contract_listing_marker`
  * Any number of outputs to other addresses if needed (not validated)
  * Burning exactly one `contract_listing_marker` per listing input
  * Signature of `listing_operator_credential`

---

### **5. Cleaning**

Removal of garbage UTXOs at the contract address.

* Mandatory:

  * Reference to the valid `config eUTxO`
  * One or more inputs from the contract address **without** any of:

    * `contract_order_marker`
    * `contract_config_marker`
    * `contract_listing_marker`
  * Any number of inputs from other addresses if needed (not validated)
  * Minting is **forbidden**
  * Operator signature (`contract_operator_keyhash`)

---

### **6. Order Placing**

User places a new order.

An order may also be placed by the operator on behalf of a user when needed (e.g., migrating orders between contract versions). In that case, the user's signature is not required; the operator signature is sufficient.

* Mandatory:

  * Reference to a valid `listing eUTxO`
  * Reference to the valid `config eUTxO`
  * Exactly one output to the contract address (index 0) containing:

    * 1 token `contract_order_marker`
    * a valid `OrderDatum`
    * the required locked funds for the order type
    * `contract_order_min_ada` ADA
  * Any number of outputs to other addresses if needed (not validated)
  * Minting exactly one `contract_order_marker`
  * Validity range:

    * Optional when `timeout` is `0`
    * If `timeout` is set, the upper bound must be **before** the timeout
  * Signature of `order_maker_keyhash` (or `contract_operator_keyhash` when the operator places the order on behalf of the user)

---

### **7. Order Changing**

Modification of an existing order.

* Mandatory:

  * Reference to the valid `config eUTxO`
  * Reference to a valid listing eUTxO
  * Exactly one input from the contract address with `contract_order_marker`
  * Exactly one output to the contract address (index 0) containing:

    * 1 token `contract_order_marker`
    * a valid `OrderDatum`
    * the required locked funds for the new order configuration
    * `contract_order_min_ada` ADA
  * Any number of outputs to other addresses if needed (not validated)
  * Minting is **forbidden**
  * Signatures:

    * `order_maker_keyhash` from the spent order
    * `order_maker_keyhash` from the new order if it changes

---

### **8. Order Canceling**

Cancellation by the order owner or the operator.

* Mandatory:

  * Reference to the valid `config eUTxO`
  * Exactly one input from the contract address with `contract_order_marker`
  * One output to the address specified by `order_maker_keyhash` that returns the locked funds (index 0)
  * Any number of outputs to other addresses if needed (not validated)
  * Burning exactly one `contract_order_marker`
  * Validity range:

    * Optional if cancellation is authorized (owner or operator)
    * If unauthorized, the upper bound must be **after** the timeout
  * Signatures:

    * `order_maker_keyhash` **or** `contract_operator_keyhash`

---

### **9. Order Execution**

A user accepts an order and executes the trade.

* Mandatory:

  * Reference to the valid `config eUTxO`
  * Reference to a valid listing eUTxO
  * Exactly one input from the contract address with `contract_order_marker`
  * Outputs:

    * Output to the maker (index 0) with the proceeds
    * Output to the taker (index 1) with the traded asset/ADA
    * Output to the platform fee address index 2) with the computed fee (not less than `platform_fee_min_amount`)
    * Optional output to the contract (index 3) for **partial** execution, containing:

      * `contract_order_marker`
      * updated `OrderDatum` (only the remaining amount changes)
      * remaining locked funds and `contract_order_min_ada`
    * Any number of outputs to other addresses if needed (not validated)
  * Minting:

    * Positive minting is forbidden
    * If fully executed, burn `contract_order_marker`
    * If partially executed, burning is forbidden
  * Validity range:

    * Must be invalid **after** the timeout in the input datum
    * Optional if timeout is `0`
  * Partial execution is allowed only if `partial_fulfillment_allowed` is `True`
