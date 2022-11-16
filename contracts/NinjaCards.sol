// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

error NinjaCards__NotEnoughMintFee();
error NinjaCards__WithdrawalFailed();

contract NinjaCards is VRFConsumerBaseV2, ERC721URIStorage, Ownable {
    // NFT variables
    uint256 internal immutable i_mintFee;
    mapping(uint256 => address) public s_requestIdToSender; // a mapping from requestId to the address that made that request
    uint256 private s_tokenCounter;
    string[] internal s_ninjaTokenURIs = [
        "ipfs://QmZEYCAm6go1X2sRc9h2BHmSgKzBwsSR26SvFcm1JavCWE",
        "ipfs://QmSFf5WNMpiUNB7bpCAK4KhyvvQZDaQNMcHgYFmewoNAuA",
        "ipfs://QmTXSbmHnXzPqFpJxvhCmMDJ8vq4STzXFyipSxx6ZMA9he",
        "ipfs://QmfXZEUQw191DUVxKwnggacA3HkGJaQTiYyfTPCYskMvs2"
    ]; // [Hokage, Jonin, Chunin, Genin]

    enum NinjaType {
        HOKAGE, // 0th item
        JONIN, // 1st item
        CHUNIN, // 2nd item
        GENIN // 3rd item
    }

    // Chainlink VRF variables
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId; // get subscription ID from vrf.chain.link
    bytes32 private immutable i_keyHash;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;

    // Events
    event NftRequested(uint256 indexed requestId, address requester);
    event NftMinted(NinjaType ninjaType, address minter);

    constructor(
        uint256 mintFee,
        address vrfCoordinatorV2Address,
        uint64 subId,
        bytes32 keyHash,
        uint32 callbackGasLimit
    )
        VRFConsumerBaseV2(vrfCoordinatorV2Address)
        ERC721("Ninja Cards", "NINJA")
    {
        i_mintFee = mintFee;
        s_tokenCounter = 0;

        // VRF variables
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2Address);
        i_subscriptionId = subId;
        i_keyHash = keyHash;
        i_callbackGasLimit = callbackGasLimit;
    }

    function requestNFT() public payable returns (uint256 requestId) {
        // check if mintFee is paid
        if (msg.value < i_mintFee) {
            revert NinjaCards__NotEnoughMintFee();
        }

        requestId = i_vrfCoordinator.requestRandomWords(
            i_keyHash, //
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        s_requestIdToSender[requestId] = msg.sender; // map the caller to their respective requestIDs.

        // emit an event
        emit NftRequested(requestId, msg.sender);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords)
        internal
        override
    {
        // Step 1 - figure out nftOwner
        address nftOwner = s_requestIdToSender[requestId]; // map the requestId to whoever sent the request for Randomness

        // Step 2 - mint the NFT
        uint256 tokenId = s_tokenCounter; // assign unique tokenId

        // figure out which NFT to mint
        // create a randomNumber by modding the value provided by VRF through randomWords[] array
        uint256 randomNumber = randomWords[0] % 100; // get a random number between 0 - 99

        NinjaType ninjaType = getNinjaRarity(randomNumber); // get which random NinjaCard to mint
        _safeMint(nftOwner, tokenId); // finally, mint the NFT using _safeMint function

        // set Token URI of that particular NFT
        _setTokenURI(tokenId, s_ninjaTokenURIs[uint256(ninjaType)]); // takes tokenID and tokenURI
        s_tokenCounter += 1; // increment the token count

        // emit event
        emit NftMinted(ninjaType, nftOwner);
    }

    function getNinjaRarity(uint256 randomNumber)
        public
        pure
        returns (NinjaType)
    {
        uint256 cumulativeSum = 0;
        uint8[4] memory chanceArray = getChanceArray();

        // loop through chanceArray: [10,25, 50, 100]
        for (uint256 i = 0; i < chanceArray.length; i++) {
            if (
                randomNumber >= cumulativeSum && randomNumber < chanceArray[i]
            ) {
                // if randomNumber: 0-9 => Hokage
                // 10-24 => Jonin
                // 25-49 => Chunin
                // 50-99 => Genin
                return NinjaType(i);
            }
            cumulativeSum = chanceArray[i];
        }
    }

    function getChanceArray() public pure returns (uint8[4] memory) {
        // index 0 -> 10-0: 10% chance: Hokage
        // index 1: 25-10: 15% chance: Jonin
        // index 2: 50-25: 25% chance: Chunin
        // index 3: 100-50: 50% chance: Genin
        return [10, 25, 50, 100];
    }

    function withdraw() public onlyOwner {
        uint256 amount = address(this).balance;
        (bool success, ) = payable(msg.sender).call{value: amount}("");

        if (!success) {
            revert NinjaCards__WithdrawalFailed();
        }
    }

    // View Functions
    function getMintFee() public view returns (uint256) {
        return i_mintFee;
    }

    function getTokenURIs(uint256 index) public view returns (string memory) {
        return s_ninjaTokenURIs[index];
    }

    function getTokenCounter() public view returns (uint256) {
        return s_tokenCounter;
    }
}
