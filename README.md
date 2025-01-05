## Aave Leverage Manager

> [!CAUTION]
> I have no idea what I'm doing, this is purely for educational purposes. Don't use this in production.

A smart contract that manages a leveraged ETH position in Aave, inspired by [Index Coop](https://indexcoop.com/). It represents ownership as an ERC20 token, and allows anybody to rebalance the Aave position at any time.

This repo also includes a [keeper](./keeper/README.md) script that monitors the health of the position and rebalances it if necessary.

## Deployments

- Base: [`0x271f0fa3852c9bb8940426a74cb987a354ed2553`](https://basescan.org/address/0x271f0fa3852c9bb8940426a74cb987a354ed2553).

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
$ forge script script/ETH2X.s.sol:ETH2XScript --rpc-url <your_rpc_url> --private-key <your_private_key>
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
