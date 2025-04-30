;; fuelchain-core.clar
;; FuelChain Core Contract
;; This contract manages fuel tokenization, ownership, and transfer throughout the supply chain.
;; It enables the creation, tracking, and transfer of fuel assets from refineries to end consumers
;; while maintaining an immutable record of each batch's journey and specifications.

;; =============================
;; Constants & Error Codes
;; =============================

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PARTICIPANT (err u101))
(define-constant ERR-BATCH-NOT-FOUND (err u102))
(define-constant ERR-INVALID-BATCH-ID (err u103))
(define-constant ERR-UNAUTHORIZED-TRANSFER (err u104))
(define-constant ERR-RECIPIENT-NOT-AUTHORIZED (err u105))
(define-constant ERR-INVALID-QUALITY-RATING (err u106))
(define-constant ERR-INVALID-VOLUME (err u107))
(define-constant ERR-ALREADY-REGISTERED (err u108))
(define-constant ERR-BATCH-ALREADY-EXISTS (err u109))

;; Role types for supply chain participants
(define-constant ROLE-ADMIN u1)
(define-constant ROLE-REFINERY u2)
(define-constant ROLE-TRANSPORTER u3)
(define-constant ROLE-DISTRIBUTOR u4)
(define-constant ROLE-RETAILER u5)
(define-constant ROLE-REGULATOR u6)

;; Fuel types
(define-constant FUEL-GASOLINE u1)
(define-constant FUEL-DIESEL u2)
(define-constant FUEL-JET u3)
(define-constant FUEL-NATURAL-GAS u4)
(define-constant FUEL-BIOFUEL u5)

;; Status constants
(define-constant STATUS-CREATED u1)
(define-constant STATUS-IN-TRANSIT u2)
(define-constant STATUS-AT-DISTRIBUTOR u3)
(define-constant STATUS-AT-RETAILER u4)
(define-constant STATUS-SOLD u5)

;; =============================
;; Data Maps & Variables
;; =============================

;; Mapping of participants and their roles
(define-map participants 
  { address: principal } 
  { 
    role: uint,
    name: (string-ascii 50),
    active: bool,
    fuel-types-authorized: (list 10 uint)
  }
)

;; Core fuel batch data
(define-map fuel-batches 
  { batch-id: uint } 
  {
    fuel-type: uint,
    volume: uint,
    quality-rating: uint,
    owner: principal,
    current-location: principal,
    status: uint,
    created-at: uint,
    last-updated: uint
  }
)

;; Detailed specifications for each fuel batch
(define-map batch-specifications
  { batch-id: uint }
  {
    refinery: principal,
    octane-rating: uint,
    sulfur-content: uint,
    additives: (string-ascii 100),
    certification-date: uint
  }
)

;; Transfer history for each batch
(define-map transfer-history
  { batch-id: uint, transfer-id: uint }
  {
    from: principal,
    to: principal,
    timestamp: uint,
    previous-status: uint,
    new-status: uint,
    price: uint,
    notes: (string-ascii 200)
  }
)

;; Counter for transfer IDs
(define-data-var transfer-id-counter uint u0)

;; Counter for batch IDs
(define-data-var batch-id-counter uint u0)

;; Contract administrator
(define-data-var contract-admin principal tx-sender)

;; =============================
;; Private Functions
;; =============================

;; Check if principal is admin
(define-private (is-admin (caller principal))
  (is-eq caller (var-get contract-admin))
)

;; Check if principal has a specific role
(define-private (has-role (caller principal) (role-id uint))
  (match (map-get? participants { address: caller })
    participant (and (is-eq (get role participant) role-id)
                     (get active participant))
    false
  )
)

;; Check if principal is authorized for a specific fuel type
(define-private (is-authorized-for-fuel (caller principal) (fuel-type uint))
  (match (map-get? participants { address: caller })
    participant (and (get active participant)
                    (is-some (index-of (get fuel-types-authorized participant) fuel-type)))
    false
  )
)

;; Get the next transfer ID and increment the counter
(define-private (get-next-transfer-id)
  (let ((current-id (var-get transfer-id-counter)))
    (var-set transfer-id-counter (+ current-id u1))
    current-id
  )
)

;; Get the next batch ID and increment the counter
(define-private (get-next-batch-id)
  (let ((current-id (var-get batch-id-counter)))
    (var-set batch-id-counter (+ current-id u1))
    current-id
  )
)

;; =============================
;; Read-Only Functions
;; =============================

;; Get participant information
(define-read-only (get-participant (address principal))
  (map-get? participants { address: address })
)

;; Get fuel batch information
(define-read-only (get-fuel-batch (batch-id uint))
  (map-get? fuel-batches { batch-id: batch-id })
)

;; Get batch specifications
(define-read-only (get-batch-specifications (batch-id uint))
  (map-get? batch-specifications { batch-id: batch-id })
)

;; Get specific transfer from history
(define-read-only (get-transfer (batch-id uint) (transfer-id uint))
  (map-get? transfer-history { batch-id: batch-id, transfer-id: transfer-id })
)

;; Check if caller is authorized to own a specific fuel type
(define-read-only (can-handle-fuel-type (address principal) (fuel-type uint))
  (is-authorized-for-fuel address fuel-type)
)

;; Check batch ownership
(define-read-only (is-batch-owner (address principal) (batch-id uint))
  (match (map-get? fuel-batches { batch-id: batch-id })
    batch (is-eq (get owner batch) address)
    false
  )
)

;; =============================
;; Public Functions
;; =============================

;; Register a new participant in the supply chain
(define-public (register-participant 
                (address principal) 
                (role uint) 
                (name (string-ascii 50))
                (fuel-types-authorized (list 10 uint)))
  (begin
    ;; Only admin can register participants
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Check if role is valid
    (asserts! (and (>= role ROLE-ADMIN) (<= role ROLE-REGULATOR)) ERR-INVALID-PARTICIPANT)
    
    ;; Check if participant already exists
    (asserts! (is-none (map-get? participants { address: address })) ERR-ALREADY-REGISTERED)
    
    ;; Register the participant
    (map-set participants 
      { address: address } 
      { 
        role: role,
        name: name,
        active: true,
        fuel-types-authorized: fuel-types-authorized
      }
    )
    
    (ok true)
  )
)

;; Update participant information
(define-public (update-participant 
                (address principal) 
                (role uint) 
                (name (string-ascii 50))
                (active bool)
                (fuel-types-authorized (list 10 uint)))
  (begin
    ;; Only admin can update participants
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Check if role is valid
    (asserts! (and (>= role ROLE-ADMIN) (<= role ROLE-REGULATOR)) ERR-INVALID-PARTICIPANT)
    
    ;; Check if participant exists
    (asserts! (is-some (map-get? participants { address: address })) ERR-INVALID-PARTICIPANT)
    
    ;; Update the participant
    (map-set participants 
      { address: address } 
      { 
        role: role,
        name: name,
        active: active,
        fuel-types-authorized: fuel-types-authorized
      }
    )
    
    (ok true)
  )
)

;; Create a new fuel batch (refineries only)
(define-public (create-fuel-batch 
                (fuel-type uint) 
                (volume uint) 
                (quality-rating uint)
                (octane-rating uint)
                (sulfur-content uint)
                (additives (string-ascii 100)))
  (let ((new-batch-id (get-next-batch-id))
        (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
    
    ;; Check if caller is a refinery
    (asserts! (has-role tx-sender ROLE-REFINERY) ERR-NOT-AUTHORIZED)
    
    ;; Check if refinery is authorized for this fuel type
    (asserts! (is-authorized-for-fuel tx-sender fuel-type) ERR-UNAUTHORIZED-TRANSFER)
    
    ;; Validate input data
    (asserts! (and (>= fuel-type FUEL-GASOLINE) (<= fuel-type FUEL-BIOFUEL)) ERR-INVALID-BATCH-ID)
    (asserts! (> volume u0) ERR-INVALID-VOLUME)
    (asserts! (and (>= quality-rating u1) (<= quality-rating u10)) ERR-INVALID-QUALITY-RATING)
    
    ;; Register the batch
    (map-set fuel-batches
      { batch-id: new-batch-id }
      {
        fuel-type: fuel-type,
        volume: volume,
        quality-rating: quality-rating,
        owner: tx-sender,
        current-location: tx-sender,
        status: STATUS-CREATED,
        created-at: current-time,
        last-updated: current-time
      }
    )
    
    ;; Store the detailed specifications
    (map-set batch-specifications
      { batch-id: new-batch-id }
      {
        refinery: tx-sender,
        octane-rating: octane-rating,
        sulfur-content: sulfur-content,
        additives: additives,
        certification-date: current-time
      }
    )
    
    (ok new-batch-id)
  )
)

;; Transfer a fuel batch to another participant
(define-public (transfer-batch 
                (batch-id uint) 
                (recipient principal) 
                (new-status uint)
                (price uint)
                (notes (string-ascii 200)))
  (let ((current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
    
    ;; Check if batch exists
    (match (map-get? fuel-batches { batch-id: batch-id })
      batch 
      (begin
        ;; Verify sender is the current owner
        (asserts! (is-eq (get owner batch) tx-sender) ERR-NOT-AUTHORIZED)
        
        ;; Verify recipient is registered
        (match (map-get? participants { address: recipient })
          recipient-data
          (begin
            ;; Verify recipient is active
            (asserts! (get active recipient-data) ERR-INVALID-PARTICIPANT)
            
            ;; Verify recipient is authorized for this fuel type
            (asserts! (is-authorized-for-fuel recipient (get fuel-type batch)) ERR-RECIPIENT-NOT-AUTHORIZED)
            
            ;; Verify new status is valid
            (asserts! (and (>= new-status STATUS-IN-TRANSIT) (<= new-status STATUS-SOLD)) ERR-UNAUTHORIZED-TRANSFER)
            
            ;; Create transfer record
            (let ((transfer-id (get-next-transfer-id)))
              (map-set transfer-history
                { batch-id: batch-id, transfer-id: transfer-id }
                {
                  from: tx-sender,
                  to: recipient,
                  timestamp: current-time,
                  previous-status: (get status batch),
                  new-status: new-status,
                  price: price,
                  notes: notes
                }
              )
              
              ;; Update batch information
              (map-set fuel-batches
                { batch-id: batch-id }
                {
                  fuel-type: (get fuel-type batch),
                  volume: (get volume batch),
                  quality-rating: (get quality-rating batch),
                  owner: recipient,
                  current-location: recipient,
                  status: new-status,
                  created-at: (get created-at batch),
                  last-updated: current-time
                }
              )
              
              (ok transfer-id)
            )
          )
          ERR-INVALID-PARTICIPANT
        )
      )
      ERR-BATCH-NOT-FOUND
    )
  )
)

;; Update batch status without changing ownership
(define-public (update-batch-status 
                (batch-id uint) 
                (new-status uint)
                (notes (string-ascii 200)))
  (let ((current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
    
    ;; Check if batch exists
    (match (map-get? fuel-batches { batch-id: batch-id })
      batch 
      (begin
        ;; Verify sender is the current owner
        (asserts! (is-eq (get owner batch) tx-sender) ERR-NOT-AUTHORIZED)
        
        ;; Verify new status is valid
        (asserts! (and (>= new-status STATUS-CREATED) (<= new-status STATUS-SOLD)) ERR-UNAUTHORIZED-TRANSFER)
        
        ;; Create status update record
        (let ((transfer-id (get-next-transfer-id)))
          (map-set transfer-history
            { batch-id: batch-id, transfer-id: transfer-id }
            {
              from: tx-sender,
              to: tx-sender,
              timestamp: current-time,
              previous-status: (get status batch),
              new-status: new-status,
              price: u0,
              notes: notes
            }
          )
          
          ;; Update batch information
          (map-set fuel-batches
            { batch-id: batch-id }
            {
              fuel-type: (get fuel-type batch),
              volume: (get volume batch),
              quality-rating: (get quality-rating batch),
              owner: tx-sender,
              current-location: tx-sender,
              status: new-status,
              created-at: (get created-at batch),
              last-updated: current-time
            }
          )
          
          (ok transfer-id)
        )
      )
      ERR-BATCH-NOT-FOUND
    )
  )
)

;; Split a batch into two parts (for partial transfers)
(define-public (split-batch 
                (batch-id uint) 
                (split-volume uint))
  (let ((current-time (unwrap-panic (get-block-info? time (- block-height u1))))
        (new-batch-id (get-next-batch-id)))
    
    ;; Check if batch exists
    (match (map-get? fuel-batches { batch-id: batch-id })
      batch 
      (begin
        ;; Verify sender is the current owner
        (asserts! (is-eq (get owner batch) tx-sender) ERR-NOT-AUTHORIZED)
        
        ;; Verify split volume is valid
        (asserts! (and (> split-volume u0) (< split-volume (get volume batch))) ERR-INVALID-VOLUME)
        
        ;; Get original specifications
        (match (map-get? batch-specifications { batch-id: batch-id })
          specs
          (begin
            ;; Create new batch with split volume
            (map-set fuel-batches
              { batch-id: new-batch-id }
              {
                fuel-type: (get fuel-type batch),
                volume: split-volume,
                quality-rating: (get quality-rating batch),
                owner: tx-sender,
                current-location: tx-sender,
                status: (get status batch),
                created-at: current-time,
                last-updated: current-time
              }
            )
            
            ;; Copy specifications to new batch
            (map-set batch-specifications
              { batch-id: new-batch-id }
              {
                refinery: (get refinery specs),
                octane-rating: (get octane-rating specs),
                sulfur-content: (get sulfur-content specs),
                additives: (get additives specs),
                certification-date: (get certification-date specs)
              }
            )
            
            ;; Update original batch with reduced volume
            (map-set fuel-batches
              { batch-id: batch-id }
              {
                fuel-type: (get fuel-type batch),
                volume: (- (get volume batch) split-volume),
                quality-rating: (get quality-rating batch),
                owner: tx-sender,
                current-location: tx-sender,
                status: (get status batch),
                created-at: (get created-at batch),
                last-updated: current-time
              }
            )
            
            ;; Create a record of the split
            (let ((transfer-id (get-next-transfer-id)))
              (map-set transfer-history
                { batch-id: batch-id, transfer-id: transfer-id }
                {
                  from: tx-sender,
                  to: tx-sender,
                  timestamp: current-time,
                  previous-status: (get status batch),
                  new-status: (get status batch),
                  price: u0,
                  notes: (concat "Split into new batch #" (to-ascii new-batch-id))
                }
              )
              
              (ok new-batch-id)
            )
          )
          ERR-BATCH-NOT-FOUND
        )
      )
      ERR-BATCH-NOT-FOUND
    )
  )
)

;; Change contract administrator
(define-public (set-contract-admin (new-admin principal))
  (begin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (var-set contract-admin new-admin)
    (ok true)
  )
)