# Jobs Protocol Spec

## Deployments (Verified on Basescan)

ReadAPI: 0x9795aE5b774748D386089f49D75161492119B7CA

JobBoard: 0x2D2BB82ab894267C5Ba80D26e9B4f7470315Bdd8

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
