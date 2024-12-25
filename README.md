## Aave Leverage Manager

> [!CAUTION]
> I have no idea what I'm doing, this is purely for educational purposes. Don't use this in production.

A smart contract that manages a leveraged ETH position in Aave, inspired by [Index Coop](https://indexcoop.com/). It represents ownership as an ERC20 token, and allows anybody to rebalance the Aave position at any time.

## Foundry Documentation

https://book.getfoundry.sh/

## Usage

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
