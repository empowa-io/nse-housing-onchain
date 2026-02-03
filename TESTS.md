# Test Summary

## tests/bootstrap

Suite: Test suite for the contract launch phase. Bootstrapping can only be performed once, so we must ensure everything goes through without errors. Mostly checks that protect against human error in case the operator makes a mistake.
Validation: mint

| Test Name | Test Case Description | Type (fail/success) | Status (PASSED/FAILED) |
| --- | --- | --- | --- |
| succes_bootstrap | Successful bootstrap where the operator correctly registers the configuration eUTXO. | success | PASSED |
| failed_bad_inputs | User provided 2 inputs, but exactly one input is required. | fail | PASSED |
| failed_bad_bootstrap_utxo_hash | Bootstrap input references the wrong UTxO hash (expected contract_bootstrap_utxo_hash). | fail | PASSED |
| failed_bad_bootstrap_utxo_index | Bootstrap input references the wrong UTxO index (expected contract_bootstrap_utxo_index). | fail | PASSED |
| failed_many_contract_outputs | User included more than one contract output to the contract address, but exactly one is required. | fail | PASSED |
| failed_bad_outputs_position | Contract output is not at index 0 (it must be the first output). | fail | PASSED |
| failed_no_marker_in_contract_output | Contract output does not contain the required configuration marker token. | fail | PASSED |
| failed_output_has_no_datum | Contract output is missing the required inline datum (ConfigDatum). | fail | PASSED |
| failed_output_has_bad_datum | Contract output has a datum of the wrong type (expected ConfigDatum). | fail | PASSED |
| failed_bad_minting_policy_id | Marker is minted under the wrong policy id (expected contract_policy_id). | fail | PASSED |
| failed_bad_minting_asset_name | Marker is minted with the wrong asset name (expected contract_config_marker). | fail | PASSED |
| failed_bad_minting_amount | Marker is minted with the wrong quantity (expected exactly 1). | fail | PASSED |
| failed_bad_minting_extra_asset | Transaction mints extra assets in addition to the required marker (only the marker must be minted). | fail | PASSED |
| failed_bad_signature | User provided an incorrect extra signatory; the required operator signature is missing. | fail | PASSED |

## tests/cleaning

Suite: Test suite for the contract address cleaning action. For various reasons, garbage can accumulate at the contract address: Garbage is defined as UTXOs created without the smart contract's involvement.
Validation: spend

| Test Name | Test Case Description | Type (fail/success) | Status (PASSED/FAILED) |
| --- | --- | --- | --- |
| success_cleaning | Successful garbage cleanup attempt. | success | PASSED |
| fail_no_config_ref_input | The user did not include the config to bypass authentication. | fail | PASSED |
| fail_order_marker_on_input | Attempt to remove a UTXO that contains contract_order_marker. | fail | PASSED |
| fail_config_marker_on_input | Attempt to remove a UTXO that contains contract_config_marker. | fail | PASSED |
| fail_listing_marker_on_input | Attempt to remove a UTXO that contains contract_listing_marker. | fail | PASSED |
| fail_tx_contains_minting_by_contract | Attempt to mint something on behalf of the contract. | fail | PASSED |
| fail_tx_contains_minting_by_3rd_party | Attempt to mint something on behalf of a third-party policy. | fail | PASSED |
| fail_missing_operator_signature | The user did not provide the operator signature and is trying to bypass authentication. | fail | PASSED |

## tests/configuration

Suite: Test suite for the contract reconfiguration. Technically, this is almost the same operation as bootstrap, differing only by: forbidding minting/burning of `contract_policy_id.contract_config_marker`.
Validation: spend

| Test Name | Test Case Description | Type (fail/success) | Status (PASSED/FAILED) |
| --- | --- | --- | --- |
| success_and_operator_changed | Successful configureation where the operator correctly changes the configuration eUTXO. Needs two extra signatures. | success | PASSED |
| success_and_operator_not_changed | Successful configureation where the operator correctly changes the configuration eUTXO. Needs Only one signature. | success | PASSED |
| failed_operator_changed_without_new_signature | Case where the operator tries to transfer control to another party without their signature. If allowed, there is a risk of losing control because ownership of the new keys is not confirmed. A minor typo could mean losing control of the contract forever. | fail | PASSED |
| failed_operator_changed_without_old_signature | Case where the operator tries to transfer control to another party, but didn't sign it. | fail | PASSED |
| failed_bad_outputs_position | Contract output is not at index 0 (it must be the first output). | fail | PASSED |
| failed_bad_inputs | User provided 2 inputs, but exactly one input is required. | fail | PASSED |
| failed_bad_outputs | Contract output does not contain the required configuration marker token. | fail | PASSED |
| failed_no_datum | Contract output is missing the required inline datum (ConfigDatum). | fail | PASSED |
| failed_bad_datum | Contract output has a datum of the wrong type (expected ConfigDatum). | fail | PASSED |
| failed_minting_presents | Transaction performs minting, but minting is forbidden for this action. | fail | PASSED |

## tests/delisting

Suite: Test suite for the asset delisting action. Works as the inverse of listing: listing UTXOs are consumed as inputs.
Validation: spend+mint

| Test Name | Test Case Description | Type (fail/success) | Status (PASSED/FAILED) |
| --- | --- | --- | --- |
| success_delisting | Since only the marker presence is validated, the input type (wildcard/no_wildcard). does not affect anything and does not require separate coverage. | success | PASSED |
| success_delisting_many_assets | Successful removal of multiple listings in a single transaction. | success | PASSED |
| failed_no_conf_reference_input | User forgot to include the correct config. | fail | PASSED |
| failed_bad_conf_reference_input | User attached a third-party config to bypass authentication. | fail | PASSED |
| failed_input_without_listing_marker | User attempts to delist without a listing marker on the input. | fail | PASSED |
| failed_marker_burn_mismatch | User burned fewer markers than spent listing inputs. Attempt to move a marker to an external address. | fail | PASSED |
| failed_marker_burn_not_marker_only | User burned or minted something else other than marker. | fail | PASSED |
| failed_no_operator_signature | User forgot to add the listing operator signature. | fail | PASSED |
| failed_bad_operator_signature | User provided an incorrect listing operator signature. | fail | PASSED |

## tests/listing

Suite: Test suite for the asset listing action. Note: working with listings requires a separate `listing_operator_credential` role. This adds flexibility by allowing responsibilities to be split.
Validation: mint

| Test Name | Test Case Description | Type (fail/success) | Status (PASSED/FAILED) |
| --- | --- | --- | --- |
| success_listing_wildcard | Successful listing transaction using a wildcard listing (asset name is not fixed). | success | PASSED |
| success_listing_no_wildcard | Successful listing transaction using a non-wildcard listing (asset name is fixed). | success | PASSED |
| success_listing_many_assets | Successful listing transaction creating multiple listing outputs in a single transaction. | success | PASSED |
| failed_no_conf_reference_input | User forgot to include the correct config. | fail | PASSED |
| failed_bad_conf_reference_input | User attached a third-party config to bypass authentication. | fail | PASSED |
| failed_contract_outputs_marker_mismatch_GT | Attempt to mint something other than the marker on behalf of the contract. | fail | PASSED |
| failed_contract_outputs_marker_mismatch_LT | For some reason the number of `contract_policy_id.contract_listing_marker` markers. and valid outputs do not match. - fewer markers than outputs. | fail | PASSED |
| failed_bad_listing_datum | User made an error in the datum. | fail | PASSED |
| failed_no_listing_datum | User forgot to include the datum. | fail | PASSED |
| failed_bad_listing_datum_empty_policy | User supplied an empty policy_id. This is not a problem, but it is better to reject clearly invalid transactions, even if they are safe for the contract. | fail | PASSED |
| failed_bad_listing_datum_empty_asset_name | User supplied an empty asset_name instead of None. This is not a problem, but it is better to reject clearly invalid transactions, even if they are safe for the contract. | fail | PASSED |
| failed_bad_mint_not_only_markers | For some reason the number of `contract_policy_id.contract_listing_marker` markers. and valid outputs do not match. - more markers than outputs. | fail | PASSED |
| failed_no_marker_minted | User forgot to mint `contract_policy_id.contract_listing_marker`. | fail | PASSED |
| failed_no_operator_signature | User forgot to add the listing operator signature. Or intentionally tries to bypass contract authentication. | fail | PASSED |
| failed_bad_operator_signature | User provided an incorrect listing operator signature. Or intentionally tries to bypass contract authentication. | fail | PASSED |

## tests/order_canceling

Suite: Test suite for the order canceling action. An order before the timeout expires can be closed either by the contract operator or the order owner. The order can be closed at any moment on demand.
Validation: spend+mint

| Test Name | Test Case Description | Type (fail/success) | Status (PASSED/FAILED) |
| --- | --- | --- | --- |
| success_order_canceling_authorized_owner | Successful attempt to cancel the order by its owner. | success | PASSED |
| success_order_canceling_authorized_operator | Successful attempt to cancel the order by the contract operator. | success | PASSED |
| success_order_canceling_unauthorized | Successful attempt to cancel the order without authorization (after timeout). | success | PASSED |
| fail_no_config_reference | The user forgot to include the config reference. | fail | PASSED |
| fail_bad_config_reference_utxo | The user provided a link to another utxo at the contract address instead of the config. | fail | PASSED |
| fail_bad_config_reference_address | This prevents an attempt to provide the contract with a fake config from a different address. No other config compromise paths are expected, because it: - cannot be created with an invalid datum structure or without `contract_policy_id.contract_config_marker 1`. - cannot be created outside the contract address or moved away from it. The only realistic attack is trying to slip in a forged config from outside. | fail | PASSED |
| fail_many_orders_at_once | Attempt to close several orders at once. Technically feasible, but it would complicate the contract where simplicity is preferable. | fail | PASSED |
| fail_bad_order_utxo | Attempt to withdraw an incorrect eUTxO, for example a configuration one. | fail | PASSED |
| fail_bad_user_output_address | User specified an output address that is not linked to the keyhash in the order datum. | fail | PASSED |
| fail_bad_user_output_value | User/operator transferred less than the remaining assets from the order to the first transaction output. | fail | PASSED |
| fail_bad_user_sell_output_coin | User/operator transferred less than the remaining ada from the order to the first transaction output. We need to guarantee this cannot happen accidentally or intentionally. Especially since an expired order can be removed without authorization. | fail | PASSED |
| fail_bad_user_buy_output_coin | User/operator transferred less than the remaining ada from the order to the first transaction output. We need to guarantee this cannot happen accidentally or intentionally. Especially since an expired order can be removed without authorization. | fail | PASSED |
| fail_no_order_marker_burning | User forgot to burn the order marker when closing. | fail | PASSED |
| fail_positive_minting | User attempts to mint some asset on behalf of the contract. | fail | PASSED |
| fail_config_burning | User attempts to burn the config. | fail | PASSED |
| fail_unauthorized_canceling_before_timeout | Attempt to cancel an order without authorization before the timeout expires. | fail | PASSED |
| fail_incorrect_extra_signature | Attempt to use a signature that does not belong to the owner or operator. | fail | PASSED |

## tests/order_changing

Suite: Test suite for the order changing action. Order owner may change its configuration at any moment. Operator is not allowed to do so(!).
Validation: spend

| Test Name | Test Case Description | Type (fail/success) | Status (PASSED/FAILED) |
| --- | --- | --- | --- |
| success_order_changing | Successful attempt to change the order. | success | PASSED |
| success_order_changing_new_owner | Successful attempt to change the order and set a new owner. | success | PASSED |
| fail_no_config_reference | User forgot to attach the config to the transaction. | fail | PASSED |
| fail_bad_config_reference_utxo | Provided a reference to another UTxO instead of the config. | fail | PASSED |
| fail_bad_config_reference_address | Attempt to spoof the config with a UTxO from a different address. | fail | PASSED |
| fail_no_listing_reference | User did not attach the authorizing listing. | fail | PASSED |
| fail_bad_listing_reference | Supplying an invalid listing UTxO. | fail | PASSED |
| fail_many_orders_at_once | Attempt to change multiple orders in one transaction, which the API forbids. | fail | PASSED |
| fail_bad_order_utxo | Attempt to use a non-order input for the change. | fail | PASSED |
| fail_no_order_output | User failed to create a new order output at the contract. | fail | PASSED |
| fail_many_contract_outputs | Attempt to place multiple outputs at the contract address. | fail | PASSED |
| fail_missing_order_marker_in_output | Order marker accidentally sent to the wrong output. | fail | PASSED |
| fail_missing_order_datum | User forgot to attach the new order datum. | fail | PASSED |
| fail_bad_order_datum_type | Datum does not match the expected order structure. | fail | PASSED |
| fail_sell_order_output_no_assets | Buyer supplied only min-ADA without paying for the order. | fail | PASSED |
| fail_buy_order_output_not_enough_ada | Buyer attached less ADA than required to purchase the specified assets. | fail | PASSED |
| fail_buy_order_output_extra_ada | Buyer attached extra ADA above the required amount. | fail | PASSED |
| fail_bad_order_no_min_ada | Author forgot to include the minimal ADA on the order output. | fail | PASSED |
| fail_positive_minting | Attempt to mint anything in the order change transaction. | fail | PASSED |
| fail_negative_minting | Attempt to burn something in the order change transaction. | fail | PASSED |
| fail_missing_maker_signature | Order owner did not sign the change. | fail | PASSED |
| fail_bad_extra_signature | Operator cannot change someone else's order alone. | fail | PASSED |
| fail_missing_new_owner_signature | New owner is specified in the datum but did not sign the transaction. | fail | PASSED |
| fail_missing_previous_owner_signature | Previous owner did not sign the transfer of the order to the new owner. | fail | PASSED |
| fail_order_changing_zero_price | User set traded_asset_price to 0, but it must be greater than 0. | fail | PASSED |
| fail_order_changing_contract_output_bad_index | Contract output is not at index 0 (it must be the first output). | fail | PASSED |
| fail_order_changing_market_closed | Market is closed, user cannot change the order. | fail | PASSED |
| fail_sell_order_output_bad_min_ada | The order output does not include the exact min ADA amount. | fail | PASSED |

## tests/order_execution

Suite: Test suite for the order exetution action. An order can be accepted by any Cardano user; authorization is not required. The only sufficient condition is meeting the order terms on price and asset\ada amount.
Validation: spend[+ mint]

| Test Name | Test Case Description | Type (fail/success) | Status (PASSED/FAILED) |
| --- | --- | --- | --- |
| success_sell_full_execution | Successful attempt at full execution of an order to sell assets. | success | PASSED |
| success_sell_partial_execution | Successful attempt at partial execution of an order to sell assets. | success | PASSED |
| success_buy_full_execution | Successful attempt at full execution of an order to buy assets. | success | PASSED |
| success_buy_partial_execution | Successful attempt at partial execution of an order to buy assets. | success | PASSED |
| fail_garbage_at_order_output | The contract output containing the order must not contain foreign assets. | fail | PASSED |
| fail_garbage_at_maker_output | The maker output receiving payment must not contain foreign assets. | fail | PASSED |
| fail_missed_platform_fee | Transaction does not include the required platform fee output to the platform address. | fail | PASSED |
| fail_missed_config_utxo_ref | The user forgot to attach the config to the transaction. | fail | PASSED |
| fail_missed_listing_utxo_ref | The user forgot to attach the utxo with the listing to the transaction. | fail | PASSED |
| fail_no_ref_utxos | The user did not attach the reference utxos. | fail | PASSED |
| fail_bad_config_ref_address | This prevents an attempt to provide the contract with a fake config from a different address. No other config compromise paths are expected, because it: - cannot be created with an invalid datum structure or without `contract_policy_id.contract_config_marker 1`. - cannot be created outside the contract address or moved away from it. The only realistic attack is trying to slip in a forged config from outside. | fail | PASSED |
| fail_bad_listing_ref | User provided an invalid listing reference input (listing eUTxO does not meet requirements). | fail | PASSED |
| fail_many_order_inputs | The user tries to process several orders at once in one transaction. | fail | PASSED |
| fail_no_marker_burning_after_full_exec | The user forgot to burn the order marker when fully redeeming it, which means the marker will leave the contract address. | fail | PASSED |
| fail_marker_burning_after_partial_exec | The user tried to burn the order marker during its partial redemption, making the order invalid. | fail | PASSED |
| fail_extra_assets_minted | The user tried to mint an additional `order_marker` or any token on behalf of the contract. There is no point in checking which token is being minted because any positive minting is forbidden. | fail | PASSED |
| fail_not_only_marker_was_burned | Attempt to burn any other token besides the spent order, for example, the config. | fail | PASSED |
| fail_no_validity_range | The user forgot to specify `validity_range`. | fail | PASSED |
| fail_bad_outputs_count | The number of outputs is less than two, which is already an error because there must be two sides - buyer and seller. For example, the buyer decided to take both the assets and the payment for them... The test uses a correct buyer output, but there is no point in creating an incorrect one if only the count is validated here. | fail | PASSED |
| fail_partial_execution_when_full_only_allowed | Attempt at partial execution of an order for which this action is prohibited. It does not matter whether it is a buy or sell; what matters is violating a setting common to both cases. | fail | PASSED |
| fail_order_reconfiguration_attempt_change_owner | An attacker may try to override the order Datum to make its terms more favorable to themselves. In this case - change of the owner. | fail | PASSED |
| fail_order_reconfiguration_attempt_change_price | An attacker may try to override the order Datum to make its terms more favorable to themselves. In this case - change of the price. | fail | PASSED |
| fail_order_reconfiguration_attempt_change_asset_amount | An attacker may try to override the order Datum to make its terms more favorable to themselves. In this case - change of the order volume to take the "extra" for themselves. It is important to note that this particular change is usually legitimate if it matches the trade size. | fail | PASSED |
| fail_order_reconfiguration_attempt_change_policy_id | An attacker may try to override the order Datum to make its terms more favorable to themselves. In this case - change of the `policy_id` in order to substitute the asset with a fake one. | fail | PASSED |
| fail_order_reconfiguration_attempt_change_asset_name | An attacker may try to override the order Datum to make its terms more favorable to themselves. In this case - change of the asset name. | fail | PASSED |
| fail_order_reconfiguration_attempt_change_order_type | An attacker may try to override the order Datum to make its terms more favorable to themselves. In this case - change of the order type. | fail | PASSED |
| fail_order_reconfiguration_attempt_change_partial_execution_mode | An attacker may try to override the order Datum to make its terms more favorable to themselves. In this case - change of `partial_fulfillment_allowed`. | fail | PASSED |
| fail_order_reconfiguration_attempt_change_timeout | An attacker may try to override the order Datum to make its terms more favorable to themselves. In this case - change of the timeout. | fail | PASSED |
| fail_bad_outputs_ordering_V1 | For some reason the outputs order was mixed up. In general, strict output ordering is not required, and the contract could include automatic search for the needed ones. - But why complicate the logic where we can simply make the API stricter? - Especially since the contract does not work for free... | fail | PASSED |
| fail_bad_outputs_ordering_V2 | For some reason the outputs order was mixed up. In general, strict output ordering is not required, and the contract could include automatic search for the needed ones. - But why complicate the logic where we can simply make the API stricter? - Especially since the contract does not work for free... | fail | PASSED |
| fail_bad_contract_output_stolen_marker | The user directed the token `contract_policy_id.contract_order_marker` to the wrong output. -It does not matter whether it is a buy or sell; validation checks the fact of the token being on the contract output. | fail | PASSED |
| fail_bad_contract_output_no_datum | The user forgot to attach a datum to the updated order after partial execution. -It does not matter whether it is a buy or sell; validation checks the presence of the datum on the contract output. | fail | PASSED |
| fail_bad_contract_output_wrong_datum | The user attached an incorrect datum to the updated order after partial execution. -It does not matter whether it is a buy or sell; validation checks the datum type on the contract output. | fail | PASSED |
| fail_sell_bad_maker_output_stolen_funds_partial_exec | The buyer tries to deceive the seller by sending them not the amount (ada) they were supposed to. - by sending it to themselves. | fail | PASSED |
| fail_sell_bad_maker_output_funds_sent_to_contract_partial_exec | The buyer tries to deceive the seller by sending them not the amount (ada) they were supposed to. - by sending it to the contract (by mistake?). | fail | PASSED |
| fail_sell_bad_maker_output_stolen_funds_full_exec | The buyer tries to deceive the seller by sending them not the amount (ada) they were supposed to. - by sending it to themselves. | fail | PASSED |
| fail_buy_bad_maker_output_stolen_funds_partial_exec | The buyer tries to deceive the seller by sending them not the amount (asset) they were supposed to. - by sending it to themselves. | fail | PASSED |
| fail_buy_bad_maker_output_funds_sent_to_contract_partial_exec | The buyer tries to deceive the seller by sending them not the amount (asset) they were supposed to. - by sending it to the contract (by mistake?). | fail | PASSED |
| fail_buy_bad_maker_output_stolen_funds_full_exec | The buyer tries to deceive the seller by sending them not the amount (ada) they were supposed to. - by sending it to themselves. | fail | PASSED |
| fail_stolen_order_min_ada_partial_exec | Attempt to reduce the ada amount on the order by the `min_order_ada` deposit. It does not matter, buy or sell. | fail | PASSED |
| fail_stolen_order_min_ada_full_exec | Attempt of the taker to appropriate `min_order_ada` after its closure. It does not matter, buy or sell. | fail | PASSED |
| fail_sell_order_output_stolen_ada | Attempt of the taker to form an order with less ada than specified in its Datum to steal the rest. - Only during partial execution. | fail | PASSED |
| fail_buy_order_output_stolen_assets | Attempt of the taker to form an order with less ada than specified in its Datum to steal the rest. - Only during partial execution. | fail | PASSED |
| fail_market_closed | The market is closed by the Operator. | fail | PASSED |
| fail_bad_platform_fee | User attempts to underpay the platform fee. | fail | PASSED |
| fail_zero_platform_fee | User did not include a platform fee output at all. | fail | PASSED |

## tests/order_placing

Suite: Test suite for the order placing action. Order placing is not tied to the platform UI and can be performed by any user, including via CLI. Mostly checks that protect against human error in case the operator makes a mistake.
Validation: mint

| Test Name | Test Case Description | Type (fail/success) | Status (PASSED/FAILED) |
| --- | --- | --- | --- |
| success_sell_no_wildcard | Successful transaction placing a sell order for 42 listed assets. | success | PASSED |
| success_sell_wildcard | Successful transaction placing a sell order for 42 listed assets. | success | PASSED |
| success_buy_no_wildcard | Successful transaction placing a buy order for 42 listed assets. | success | PASSED |
| success_buy_wildcard | Successful transaction placing a buy order for 42 listed assets. | success | PASSED |
| fail_sell_not_allowed_asset_name | User tries to list an asset for sale whose `policy_id` is allowed, but `asset_name` is not. | fail | PASSED |
| failed_order_with_zero_price | What happens if a user sets the asset price to 0 ada? It does not matter whether it's BUY or SELL. | fail | PASSED |
| failed_market_is_closed | When the operator closes the market, actions authorized by regular users are not allowed. | fail | PASSED |
| failed_no_config_ref | The user forgot to attach the config to the transaction. | fail | PASSED |
| fail_bad_config_reference_utxo | The user provided a link to another utxo at the contract address instead of the config. | fail | PASSED |
| failed_bad_config_ref_address | This prevents an attempt to provide the contract with a fake config from a different address. No other config compromise paths are expected, because it: - cannot be created with an invalid datum structure or without `contract_policy_id.contract_config_marker 1`. - cannot be created outside the contract address or moved away from it. The only realistic attack is trying to slip in a forged config from outside. | fail | PASSED |
| failed_no_listing_ref | User did not include the required listing reference input (listing eUTxO). | fail | PASSED |
| failed_bad_listing_ref | This prevents an attempt to provide the contract with a wrong listing. | fail | PASSED |
| failed_no_order_output | User did not include the required contract output to the contract address. | fail | PASSED |
| failed_many_contract_outputs | The contract API forbids placing more than one output to the contract address. | fail | PASSED |
| failed_contract_output_has_bad_index | Contract outputs always have a fixed index; this must not be violated. | fail | PASSED |
| failed_bad_order_output_no_datum | Order output is missing the required inline datum (OrderDatum). | fail | PASSED |
| failed_bad_order_output_bad_datum | Order output has a datum of the wrong type (expected OrderDatum). | fail | PASSED |
| failed_bad_sell_order_output_no_assets | Scenario where the seller for some reason did not attach the assets declared in the order. | fail | PASSED |
| failed_bad_sell_order_output_not_enough_assets | Scenario where the assets attached to the order are fewer than declared in its datum. | fail | PASSED |
| failed_bad_sell_order_output_extra_assets | Scenario where the assets attached to the order are more than declared in its datum. | fail | PASSED |
| failed_bad_buy_order_output_not_enough_locked_ada | Scenario where the buyer for some reason did not attach enough ADA to purchase the assets declared in the order. Or attached less than required. Since ADA is always present in the value, it cannot be missing (unlike assets). | fail | PASSED |
| failed_bad_buy_order_output_extra_ada | Scenario where the ADA attached to the order is more than required to purchase the assets declared in the datum. | fail | PASSED |
| failed_bad_order_no_min_ada | Scenario where, when selling, the seller did not attach `min_order_ada`. | fail | PASSED |
| failed_no_order_marker_in_order_output | A situation where the marker is not minted is impossible per se, otherwise the contract would not be involved. But a situation where the minted marker is sent to the wrong output is entirely possible... | fail | PASSED |
| failed_extra_marker_mint | Attempt to place more than one order, or a single order with more than one marker. Or an attempt to "steal" the order marker from the smart contract intentionally or by mistake. No difference: any variant requires minting more than one marker and must be caught at this point. | fail | PASSED |
| failed_bad_order_timeout | User messed up the timeout? Better to reject the transaction than create an already-expired order. | fail | PASSED |
| failed_missed_extra_signature | The user forgot to require a signature by the key specified in the datum and may: - lose control over the order. - lose funds, because the key specified in the datum is tied to the address where the payout will go. | fail | PASSED |
| failed_bad_extra_signature | The user provided an incorrect signature that does not match the key in the datum, so they may: - lose control over the order. - lose funds, because the key specified in the datum is tied to the address where the payout will go. | fail | PASSED |

## Summary

- Total tests: 175
- Passed: 175
- Failed: 0
