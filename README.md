# **NSE Housing Contract**

### *(On-chain part, Cardano)*

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

  * UTXOs created without contract participation
* **Token listing and delisting**

  * By `policy_id`
  * By `policy_id + asset_name`

---

### **Order Initiator (Order Creator)**

* **Creation of a configurable order**

  * Buy order (locks ADA)
  * Sell order (locks asset)
* **Order parameter modification**
* **Early order cancellation**

  * If timeout changes are allowed, early cancellation is also allowed

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

### **1. Configuration eUTXO (CONF)**

Stores global contract parameters.

#### **Datum**

* `fee-size` (from 0 to 10000 which means from 0.00% to 100.00%)
* `operator credentials` - for the operator verification
* `listing verification key` - for the listings signature verification
* `is_market_open` - contract's switcher

#### **Assets**
Contract-issued asset **CONF** (1 unit)

#### **Rules**

* The **CONF** token may exist in **only one instance**

  * Exception: bootstrap phase
* A UTXO containing CONF may be moved only if all conditions are met:

  1. The output is moved only to the current contract address
  2. The new UTXO contains a Datum with valid parameters
  3. The transaction is signed by the active operator (extra signature)
  4. If the operator is changed, an extra signature from the **new operator** is required
     *(to validate credentials and prevent loss of control)*

---

### **2. Listing eUTXOs**

* One eUTXO per asset
* May exist **at any address** on the blockchain, as long as the Datum is valid

#### **Datum**

* `policy_id`
* `Option<asset_name>`
  * `None` means all asset names under the given policy are allowed
* Signature of sha256(`policy_id` + `asset_name`) or sha256(`policy_id`) if `asset_name` is not specified
  * Verified using the `listing verification key`

#### **Rules**

* Delisting is performed by **spending** the corresponding UTXO
* If the `listing verification key` changes:

  * All existing listings must be re-signed
  * Otherwise, the contract will reject them

---

### **3. Order eUTXOs**

* One eUTXO per order
* Must exist **only at the contract address**

#### **Creation Requirements**

1. Minting of the **ORDER** token by the contract

   * Exactly **1 unit**
   * Otherwise, the eUTXO is considered garbage
2. A reference UTXO pointing to a valid asset listing
3. A reference UTXO pointing to a valid contract configuration
4. Datum with the following structure:

   * Order type: buy / sell

     * Sell → user locks asset
     * Buy → user locks ADA
   * `policy_id` of the traded asset
   * `asset_name` of the traded asset
   * Asset amount (base units, without decimal divider)
   * Asset price (base units, without decimal divider)
   * Partial fulfillment allowed (yes / no)
   * `timeout`
   * `user credential`

     * Payment details for receiving assets / ADA
     * Used for order owner authentication
     * **Must not belong to any smart contract**
5. All order parameters may be updated by the order owner

---

## **Static Contract Parameters**

* **Bootstrap UTXO**

  * Allows initial minting of CONF and creation of the configuration eUTXO
  * Due to UTXO single-use semantics, guarantees CONF cannot be duplicated
* **Order placement deposit**

  * Amount of ADA attached to an order
  * Returned to the order owner
  * Required for:

    * Existence of the ORDER token
    * Covering fees for automatic timeout-based order cancellation

---

## **Contract Operation Modes**

### **1. Bootstrap**

Initial contract setup.

* Uses the `Bootstrap UTXO`
* Can be executed **only once**
* Mandatory:

  * Configuration structure validation
  * Operator signature

---

### **2. Configuration**

Changing contract parameters.

* Mandatory:

  * Configuration structure validation
  * Current Operator signature
  * New operator signature if needed
  * No minting allowed

---

### **3. Order Placing**

User places a new order.

Checks performed:

* Minting of exactly one ORDER token
* Valid Datum structure
* Consistency between Datum and transaction outputs
* Valid listing reference UTXO
* Valid configuration reference UTXO
* Valid `timeout` (must not be in the past, can be qual to zero if not needed)
* Sufficient ADA for the order placement deposit
* Transaction signed by the key linked to `user credential`
* Order output placed at the contract address

---

### **4. Order Changing**

Modification of an existing order.

Differences from Order Placing:

* Exactly **one existing order** must be consumed as input
* Minting or burning of the ORDER token is **forbidden**
* Requires signature:

  * From the original `user credential`
  * From the new one, if it was changed
* Conceptually, this is an order recreation transaction

---

### **5. Order Canceling**

Cancellation by the order owner or the operator.

* One or multiple orders may be consumed
* ORDER tokens of canceled orders must be burned
* Assets must be returned to addresses defined by `user credential`
* ADA in outputs:

  * Must not exceed the ADA locked in the order input
  * May be reduced to cover transaction fees

---

### **6. Order Execution**

A user accepts an order and executes the trade.

* Outputs must match the conditions defined in the order Datum
* If partial fulfillment is allowed:

  * The order is recreated
  * Similar to `Order Changing`, but:

    * No order owner signature required
    * No parameter changes allowed except asset amount
    * New amount must match the executed partial volume
* The accepting user does not lock funds in the contract

  * The exchange happens directly within the transaction
