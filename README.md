# Jobs Protocol Spec

## Deployments (Verified on Basescan)

ReadAPI: 0x1C089ACDcB501a4124CdB0C44196bB4Cdbf6cd68

JobBoard: 0x78a57863A1Bed20F82de28b5ac5CCc5F6B1b6699

Registry: 0x4011AaBAD557be4858E08496Db5B1f506a4e6167

Splitter (template): 0x7a38bb6c8ac7fb434adcb7bf445c38ec3cff19da

StakeTracker (template): 0xc090e7bba17b4c4e00455eb969d90c1323c30046


## Tests

Tests for the Rebase contract are written using Foundry.

### Setup

```
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-foundry-upgrades
forge install OpenZeppelin/openzeppelin-contracts@v4.9.6
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v4.9.6
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
