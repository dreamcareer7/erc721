pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';

import './AssetRegistryStorage.sol';

import './IERC721Base.sol';

import './IERC721Receiver.sol';

import './ERC165.sol';

contract ERC721Base is AssetRegistryStorage, IERC721Base, ERC165 {
  using SafeMath for uint256;

  //
  // Global Getters
  //

  /**
   * @dev Gets the total amount of assets stored by the contract
   * @return uint256 representing the total amount of assets
   */
  function totalSupply() public view returns (uint256) {
    return _count;
  }

  //
  // Asset-centric getter functions
  //

  /**
   * @dev Queries what address owns an asset. This method does not throw.
   * In order to check if the asset exists, use the `exists` function or check if the
   * return value of this call is `0`.
   * @return uint256 the assetId
   */
  function ownerOf(uint256 assetId) public view returns (address) {
    return _holderOf[assetId];
  }

  //
  // Holder-centric getter functions
  //
  /**
   * @dev Gets the balance of the specified address
   * @param owner address to query the balance of
   * @return uint256 representing the amount owned by the passed address
   */
  function balanceOf(address owner) public view returns (uint256) {
    return _assetsOf[owner].length;
  }

  //
  // Authorization getters
  //

  /**
   * @dev Query whether an address has been authorized to move any assets on behalf of someone else
   * @param operator the address that might be authorized
   * @param assetHolder the address that provided the authorization
   * @return bool true if the operator has been authorized to move any assets
   */
  function isApprovedForAll(address operator, address assetHolder)
    public view returns (bool)
  {
    return _operators[assetHolder][operator];
  }

  /**
   * @dev Query what address has been particularly authorized to move an asset
   * @param assetId the asset to be queried for
   * @return bool true if the asset has been approved by the holder
   */
  function getApprovedAddress(uint256 assetId) public view returns (address) {
    return _approval[assetId];
  }

  /**
   * @dev Query if an operator can move an asset.
   * @param operator the address that might be authorized
   * @param assetId the asset that has been `approved` for transfer
   * @return bool true if the asset has been approved by the holder
   */
  function isAuthorized(address operator, uint256 assetId) public view returns (bool)
  {
    require(operator != 0);
    address owner = ownerOf(assetId);
    if (operator == owner) {
      return true;
    }
    return isApprovedForAll(operator, owner) || getApprovedAddress(assetId) == operator;
  }

  //
  // Authorization
  //

  /**
   * @dev Authorize a third party operator to manage (send) msg.sender's asset
   * @param operator address to be approved
   * @param authorized bool set to true to authorize, false to withdraw authorization
   */
  function setApprovalForAll(address operator, bool authorized) public {
    if (authorized) {
      require(!isApprovedForAll(operator, msg.sender));
      _addAuthorization(operator, msg.sender);
    } else {
      require(isApprovedForAll(operator, msg.sender));
      _clearAuthorization(operator, msg.sender);
    }
    emit ApprovalForAll(operator, msg.sender, authorized);
  }

  /**
   * @dev Authorize a third party operator to manage one particular asset
   * @param operator address to be approved
   * @param assetId asset to approve
   */
  function approve(address operator, uint256 assetId) public {
    address holder = ownerOf(assetId);
    require(operator != holder);
    if (getApprovedAddress(assetId) != operator) {
      _approval[assetId] = operator;
      emit Approval(holder, operator, assetId);
    }
  }

  function _addAuthorization(address operator, address holder) private {
    _operators[holder][operator] = true;
  }

  function _clearAuthorization(address operator, address holder) private {
    _operators[holder][operator] = false;
  }

  //
  // Internal Operations
  //

  function _addAssetTo(address to, uint256 assetId) internal {
    _holderOf[assetId] = to;

    uint256 length = balanceOf(to);

    _assetsOf[to].push(assetId);

    _indexOfAsset[assetId] = length;

    _count = _count.add(1);
  }

  function _removeAssetFrom(address from, uint256 assetId) internal {
    uint256 assetIndex = _indexOfAsset[assetId];
    uint256 lastAssetIndex = balanceOf(from).sub(1);
    uint256 lastAssetId = _assetsOf[from][lastAssetIndex];

    _holderOf[assetId] = 0;

    // Insert the last asset into the position previously occupied by the asset to be removed
    _assetsOf[from][assetIndex] = lastAssetId;

    // Resize the array
    _assetsOf[from][lastAssetIndex] = 0;
    _assetsOf[from].length--;

    // Remove the array if no more assets are owned to prevent pollution
    if (_assetsOf[from].length == 0) {
      delete _assetsOf[from];
    }

    // Update the index of positions for the asset
    _indexOfAsset[assetId] = 0;
    _indexOfAsset[lastAssetId] = assetIndex;

    _count = _count.sub(1);
  }

  function _clearApproval(address holder, uint256 assetId) internal {
    if (ownerOf(assetId) == holder && _approval[assetId] != 0) {
      _approval[assetId] = 0;
      emit Approval(holder, 0, assetId);
    }
  }

  //
  // Supply-altering functions
  //

  function _generate(uint256 assetId, address beneficiary) internal {
    require(_holderOf[assetId] == 0);

    _addAssetTo(beneficiary, assetId);

    emit Transfer(0, beneficiary, assetId, msg.sender, '');
  }

  function _destroy(uint256 assetId) internal {
    address holder = _holderOf[assetId];
    require(holder != 0);

    _removeAssetFrom(holder, assetId);

    emit Transfer(holder, 0, assetId, msg.sender, '');
  }

  //
  // Transaction related operations
  //

  modifier onlyHolder(uint256 assetId) {
    require(_holderOf[assetId] == msg.sender);
    _;
  }

  modifier onlyAuthorized(uint256 assetId) {
    require(isAuthorized(msg.sender, assetId));
    _;
  }

  modifier isCurrentOwner(address from, uint256 assetId) {
    require(_holderOf[assetId] == from);
    _;
  }

  modifier isDestinataryDefined(address destinatary) {
    require(destinatary != 0);
    _;
  }

  modifier destinataryIsNotHolder(uint256 assetId, address to) {
    require(_holderOf[assetId] != to);
    _;
  }

  /**
   * @dev Alias of `safeTransferFrom(from, to, assetId, '')`
   *
   * @param from address that currently owns an asset
   * @param to address to receive the ownership of the asset
   * @param assetId uint256 ID of the asset to be transferred
   */
  function safeTransferFrom(address from, address to, uint256 assetId) public {
    return _doTransferFrom(from, to, assetId, '', msg.sender, true);
  }

  /**
   * @dev Securely transfers the ownership of a given asset from one address to
   * another address, calling the method `onNFTReceived` on the target address if
   * there's code associated with it
   *
   * @param from address that currently owns an asset
   * @param to address to receive the ownership of the asset
   * @param assetId uint256 ID of the asset to be transferred
   * @param userData bytes arbitrary user information to attach to this transfer
   */
  function safeTransferFrom(address from, address to, uint256 assetId, bytes userData) public {
    return _doTransferFrom(from, to, assetId, userData, msg.sender, true);
  }

  /**
   * @dev Transfers the ownership of a given asset from one address to another address
   * Warning! This function does not attempt to verify that the target address can send
   * tokens.
   *
   * @param from address sending the asset
   * @param to address to receive the ownership of the asset
   * @param assetId uint256 ID of the asset to be transferred
   */
  function transferFrom(address from, address to, uint256 assetId) public {
    return _doTransferFrom(from, to, assetId, '', msg.sender, false);
  }

  function _doTransferFrom(
    address from,
    address to,
    uint256 assetId,
    bytes userData,
    address operator,
    bool doCheck
  )
    onlyAuthorized(assetId)
    internal
  {
    _moveToken(from, to, assetId, userData, operator, doCheck);
  }

  function _moveToken(
    address from,
    address to,
    uint256 assetId,
    bytes userData,
    address operator,
    bool doCheck
  )
    isDestinataryDefined(to)
    destinataryIsNotHolder(assetId, to)
    isCurrentOwner(from, assetId)
    internal
  {
    address holder = _holderOf[assetId];
    _removeAssetFrom(holder, assetId);
    _clearApproval(holder, assetId);
    _addAssetTo(to, assetId);

    if (doCheck && _isContract(to)) {
      // Equals to bytes4(keccak256("onERC721Received(address,uint256,bytes)"))
      bytes4 ERC721_RECEIVED = bytes4(0xf0b9e5ba);
      require(
        IERC721Receiver(to).onERC721Received(
          holder, assetId, userData
        ) == ERC721_RECEIVED
      );
    }

    emit Transfer(holder, to, assetId, operator, userData);
  }

  /**
   * Internal function that moves an asset from one holder to another
   */

  /**
   * @dev Returns `true` if the contract implements `interfaceID` and `interfaceID` is not 0xffffffff, `false` otherwise
   * @param  _interfaceID The interface identifier, as specified in ERC-165
   */
  function supportsInterface(bytes4 _interfaceID) external view returns (bool) {

    if (_interfaceID == 0xffffffff) {
      return false;
    }
    return _interfaceID == 0x01ffc9a7 || _interfaceID == 0x7c0633c6;
  }

  //
  // Utilities
  //

  function _isContract(address addr) internal view returns (bool) {
    uint size;
    assembly { size := extcodesize(addr) }
    return size > 0;
  }
}
