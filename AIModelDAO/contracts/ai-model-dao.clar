;; AIModelDAO - Decentralized AI Model Governance
;; Allows token holders to vote on AI model parameters and funding

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PROPOSAL (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-VOTING-CLOSED (err u103))
(define-constant ERR-INSUFFICIENT-QUORUM (err u104))
(define-constant ERR-PROPOSAL-EXECUTED (err u105))
(define-constant ERR-INVALID-DELEGATE (err u106))
(define-constant ERR-TREASURY-INSUFFICIENT (err u107))
(define-constant ERR-MIN-STAKE-REQUIRED (err u108))

(define-data-var proposal-count uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var min-proposal-stake uint u1000)
(define-data-var quorum-threshold uint u30)
(define-data-var voting-period uint u1440)

(define-map proposals
  { proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    creator: principal,
    votes-for: uint,
    votes-against: uint,
    end-block: uint,
    executed: bool,
    proposal-type: (string-ascii 30),
    funding-amount: uint,
    target-address: (optional principal)
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { voted: bool, vote-type: bool, voting-power: uint }
)

(define-map dao-tokens
  { holder: principal }
  { balance: uint, staked: uint, last-claim: uint }
)

(define-map delegations
  { delegator: principal }
  { delegate: principal, voting-power: uint }
)

(define-map proposal-stakes
  { proposal-id: uint }
  { stake-amount: uint, stake-returned: bool }
)

(define-map governance-settings
  { setting: (string-ascii 30) }
  { value: uint }
)

(define-map member-roles
  { member: principal }
  { role: (string-ascii 20), permissions: uint }
)