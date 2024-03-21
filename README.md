# SparkLend Kill Switch

<!-- ![Foundry CI](https://github.com/{org}/{repo}/actions/workflows/ci.yml/badge.svg)
[![Foundry][foundry-badge]][foundry]
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/{org}/{repo}/blob/master/LICENSE) -->

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

This module registers pegged asset oracles and will trigger a lockdown mode for SparkLend if certain price thresholds are met. For example, if WBTC/BTC is observed to reach a market price of 0.95 and the threshold for this oracle is set to 0.95 then anyone can permissionlessly trigger to set SparkLend into lockdown mode which prevents new borrows on all assets.

The reasoning behind this is to limit the damage in the event of extreme market conditions. Depegging assets may be temporary, but there is no harm in an excess of caution in these situations. Users can still top up collateral and repay/withdraw in lockdown mode. This just prevents further borrowing to limit downside exposure to lenders.

The kill switch can triggered as many times as needed, but needs to be reset by the Spark Proxy under the Governance Security Module delay. MKR holders will also need to re-activate the market if it is deemed safe to do so.

## Usage

```bash
forge build
```

## Test

```bash
forge test
```

***
*The IP in this repository was assigned to Mars SPC Limited in respect of the MarsOne SP*