import assertRevert from './helpers/assertRevert'

const BigNumber = web3.BigNumber

const StandardAssetRegistry = artifacts.require('StandardAssetRegistryTest')
const Exchange =  artifacts.require('Exchange')

const NONE = '0x0000000000000000000000000000000000000000'

require('chai')
.use(require('chai-as-promised'))
.use(require('chai-bignumber')(BigNumber))
.should()

const expect = require('chai').expect;

contract('Exchange', accounts => {
  const [creator, user, anotherUser, operator, mallory] = accounts
  let registry = null
  let exchange = null
  const alternativeAsset = {id: 2, data: 'data2'}
  const sentByCreator = {from: creator}
  const sentByUser = {from: user}
  const creationParams = {
    gas: 4e6,
    gasPrice: 21e9,
    from: creator
  }
  const CONTENT_DATA = 'test data'

  beforeEach(async () => {
    registry = await StandardAssetRegistry.new(creationParams)
    exchange = await Exchange.new(registry.address)
    await registry.generate(0, creator, CONTENT_DATA, sentByCreator)
    await registry.generate(1, creator, CONTENT_DATA, sentByCreator)
  })

  describe('Exchange operations', () => {
    it('buys an specific asset', async () => {
      await registry.authorizeOperator(exchange.address, true)
      await exchange.sell(0, 100, sentByCreator)
      await exchange.buy(0, { ...sentByUser, value: 100 })
      const assets = await registry.assetsOf(user)
      const convertedAssets = assets.map(big => big.toString())
      convertedAssets.should.have.all.members(['0'])
    })

    xit('refunds remaining balance', async () => {
      const originalBalance = web3.eth.getBalance(user)
      await registry.authorizeOperator(exchange.address, true)
      await exchange.sell(0, web3.toWei(1, 'ether'), sentByCreator)
      await exchange.buy(0, { ...sentByUser, value: web3.toWei(3, 'ether') })
      const currentBalance = web3.eth.getBalance(user);
      console.log(originalBalance.toNumber(), web3.fromWei(originalBalance.toNumber(), 'ether'))
      console.log(currentBalance.toNumber(), web3.fromWei(currentBalance.toNumber(), 'ether'))
      const diff = originalBalance.toNumber() - currentBalance.toNumber()
      console.log(diff, web3.fromWei(diff, 'ether'))
      console.log(web3.fromWei(diff).toNumber())
    })

    it('reverts when buying without authorization', async () => {
      await exchange.sell(0, 100, sentByCreator)
      await assertRevert(exchange.buy(0, { ...sentByUser, value: 100 }))
    })

    it('reverts when selling a non existing asset', async () => {
      await assertRevert(exchange.sell(2, 200, sentByCreator))
    })

    it('reverts when buying an asset not on sale', async () => {
      await assertRevert(exchange.buy(2))
    })
    
    it('reverts when trying to buy with insufficent funds', async () => {
      await exchange.sell(0, 100, sentByCreator)
      await assertRevert(exchange.buy(0, { ...sentByUser, value: 50 }))
    })

    it('reverts when transfering an asset to himself', async () => {
      await registry.authorizeOperator(exchange.address, true)
      await exchange.sell(1, 1, sentByCreator)
      await assertRevert(exchange.buy(1, { ...sentByCreator, value: 1 }))
    })
  })
})
