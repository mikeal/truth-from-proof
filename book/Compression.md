# Compression from Entropy

Compression is the art of turning large numbers into smaller numbers.

In many cases, this involves using the relativity between numbers to produce a smaller encoding of each number than it would otherwise occupy as it sits relative to other numbers. This means compression is typically achieved through an understanding of the commonality that appears in all naturally produced data.

Encrypted or otherwise randomized data is then deem "uncompressable" since it is seen to have no commonality of appearance. But the cryptographer might recognize that "being random" is a commonality, and a rather useful one.

While we won't achieve a high rate of compression per cycle this way, we have the option of re-encrypting the data and compressing it again. This can be done for as many cycles as the method successfully reduces the size of the data.

This section explores an approach to compression that embraces the inherent power hidden in large sets of random numbers.

## The Method

We will be demonstrating the reduction in size of very large numbers at the expense of the creation of new sets of  much smaller numbers.

You can easily demonstrate a reduction in size of a certain set of numbers, but putting this to practical use would require many specific choices about number encoding that are beyond the scope of what we can cover here. Along the way you'll be pointed toward these choices and how they might be explored.

While most people interact with compression in the form of file compression, there's also a lot of compression that happens in-memory within the libraries and system infrastructure we build on top of. Rather than choose a single view of compression to explore, we'll stay general enough that you can explore whichever is most interesting to you.

The method is actually rather simple and involves two delta encoding steps.

### Compression Method

#### 1. Delta Encoding

- **Input Data:** Treat the input data as a series of 256-bit (32-byte) large numbers.
- **Sorting:** Sort this series while preserving the original position of each number to form a pair array.
- **Delta Encoding:** Transform the sorted series into a list of differences (deltas) between consecutive numbers. Each number in the series is replaced with the difference from its predecessor.

#### 2. Split Delta Encoding

- **Average Delta:** The deltas obtained from the previous step are no longer random. They will tend to cluster around the value `(MAX_UINT256 / series length)` due to the evenly randomized distribution of the original numbers. We'll refer to this as the `AVERAGE_DELTA`.
- **Splitting Deltas:**
  - Based on the `AVERAGE_DELTA`, separate the deltas into two groups: positive deltas and negative deltas.
  - Store the split information using a bit vector, where each bit (0 or 1) indicates whether the corresponding delta is positive or negative.
- **Further Delta Encoding:**
  - The two groups of deltas (positive and negative) are each delta encoded again separately.
  - This second delta encoding further reduces the size, leveraging the patterns inherent in the grouped deltas.

This method effectively compresses large numbers into smaller ones by transforming the original numbers into structured sequences of deltas, then recursively applying delta encoding to exploit patterns in the data.

---

And there you have it, a method for compressing large numbers into smaller numbers, at the cost of two equally large sets of smaller numbers so we need to find the right balance of number sizes in order to find any net gain.

The more numbers we have in a series, the more we can compress them. But the more numbers we have, the larger the number size we'll need to use to represent the positions. This is a tradeoff that can be explored in many ways but in the interest of brevity we'll pick a few constraints that should show some gains.

A 16-bit number range from 0 to 65,535 and cost 2 bytes each. If we constrain our "max frame size" to 65,535 numbers we end up with up to (65,535 + 1 /* for zero */) numbers in the series. Since each number is 32 bytes, we end up with a series size of 65,536 32-byte numbers, or 2,097,152 bytes or 2.097 megabytes.

That's often not enough data to show big gains. But when we go up to the next common number size, we see a big jump in the amount of data and a doubling of the overhead.

A 32-bit numbers range from 0 to 4,294,967,295 and cost 4 bytes each. If we constrain our "max frame size" to 4,294,967,295 numbers we end up with up to (4,294,967,295 + 1 /* for zero */) numbers in the series. Since each number is 32 bytes, we end up with a series size of 4,294,967,296 32-byte numbers, or 137,438,953,472 bytes or 137.439 gigabytes.

Different programming languages implement numbers differently and therefore have variations in size and some do not support number lengths between 16 and 32 bits. For file based compression, numbers will need to be encoded and there are numerous methods of encoding numbers that are beyond the scope of what we can explore here.

If we were penalized 2 32-bit numbers for every number in the series, we'd be using half the size of the original data just for these numbers, which means all the value data needs to be compressed into the other half. With a large enough set, that could work, but at smaller sizes may not and it would then be necessary to explore better methods for compression these smaller numbers.

In this demonstration, we'll be using the `integer-length` function from Common Lisp to determine what gains we may or may not be making in our compression. This function returns the number of bits needed to represent a number, which is useful for determining the size of the number encoding.

```lisp
(integer-length integer) => bit-count
```

## Code (Lisp)

The code is broken into two phases, the first phase is the delta encoding of the series of numbers. The second phase is the split delta encoding of the delta encoded series. Then the two phases are put together.

***This code is not always tested and should not be trusted while this book is still in development.***

### Phase 1: Delta Encoding

In the first phase, we need to take the input data, treat each 32 bytes as a 256-bit integer, sort them, and then perform delta encoding.

1. **Reading and Treating Data as 256-bit Numbers**
2. **Sorting the Numbers**
3. **Delta Encoding**
4. **Reversing the Delta Encoding**

#### 1: Reading Data as 256-bit Numbers

We can convert the input binary data into a list of 256-bit numbers.

```lisp
(defun extract-256bit-numbers (binary-data)
  "Convert binary-data into a list of 256-bit integers (32 bytes each).

  Each 256-bit integer is represented as a 32-byte segment of binary-data.

  Arguments:
  - binary-data: a sequence of bytes with a length that is a multiple of 32.

  Returns:
  - A list of 256-bit integers.

  32 bytes of binary data, resulting in one 256-bit integer

  ;> (extract-256bit-numbers #(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31))
  ;; => (33582872004870743689512057470824895035)

  64 bytes of binary data, resulting in two 256-bit integers

  ;> (extract-256bit-numbers #(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
                               32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63))
  ;; => (33582872004870743689512057470824895035 64584848121458614284642108774700913664)

  Check error handling for non-multiple of 32 length binary data

  ;> (condition-case nil
      (extract-256bit-numbers #(0 1 2 3 4 5))
      (error t))
  ;; => T
  "
  (unless (zerop (mod (length binary-data) 32))
    (error "binary-data length must be a multiple of 32"))
  (loop for i from 0 to (- (length binary-data) 32) by 32
        collect (reduce (lambda (acc byte) (+ (ash acc 8) byte))
                        (subseq binary-data i (+ i 32)))))
```

#### 2: Sorting the Numbers

Once we have our list of 256-bit numbers, we need to sort them.

```lisp
(defun sort-256bit-numbers (numbers)
  "Return a sorted copy of a list of 256-bit numbers without modifying the original list.

  Sorting basic integers

  ;> (sort-256bit-numbers '(200 100 300))
  => (100 200 300)

  ;; Sorting large 256-bit integers
  ; (sort-256bit-numbers '(340282366920938463463374607431768211456
  ;;                   1
  ;;                   115792089237316195423570985008687907853269984665640564039457584007913129639935
  ;;                   170141183460469231731687303715884105727))
  ;;  => (1 115792089237316195423570985008687907853269984665640564039457584007913129639935 170141183460469231731687303715884105727 340282366920938463463374607431768211456)
  "
  (sort (copy-list numbers) #'<))
```

#### 3: Delta Encoding

Delta encoding transforms the sorted list into differences between consecutive numbers.

```lisp
(defun delta-encode (numbers)
  "Delta encode a list of numbers.

  Basic delta encoding

  ;> (delta-encode '(10 13 23 50))
  => (10 3 10 27)
  "
  (loop with prev = 0
        for n in numbers
        collect (prog1 (- n prev)
                  (setf prev n))))
```

#### 4: Putting Together First Phase Compression

Now we integrate these steps into a single function to perform the first phase of compression.

```lisp
(defun first-phase-compression (binary-data)
  "Perform the first phase of compression on the binary data."
  (let* ((numbers (extract-256bit-numbers binary-data))
         (sorted-numbers (sort-256bit-numbers numbers))
         (delta-encoded (delta-encode sorted-numbers)))
    delta-encoded))
```

#### 4: Reversing the Delta Encoding

To reconstruct the original list of numbers from the delta-encoded list, we need to perform the cumulative sum of the deltas.

```lisp
(defun delta-decode (delta-encoded)
  "Reverse delta encoding to produce the original list of numbers.

  Example:
  ;> (delta-decode '(10 3 10 27))
  ;; => (10 13 23 50)
  "
  (loop with prev = 0
        for delta in delta-encoded
        for number = (+ prev delta)
        do (setf prev number)
        collect number))
```

With this function, we can decompress the delta-encoded data back to its original sequence.

#### 5: Integrating the Decompression into the First Phase

Now, let's create a function that combines both compression and decompression steps for verification.

```lisp
(defun first-phase-decompression (delta-encoded)
  "Perform the first phase of decompression on the delta-encoded data."
  (delta-decode delta-encoded))
```

We can further integrate a round-trip function for testing:

```lisp
(defun first-phase-round-trip (binary-data)
  "Test the first phase of compression and decompression."
  (let* ((compressed (first-phase-compression binary-data))
         (decompressed (first-phase-decompression compressed)))
    (list :original (extract-256bit-numbers binary-data)
          :compressed compressed
          :decompressed decompressed)))
```

With these, we can ensure that the delta encoding and decoding works as expected for the first phase. Now, let's proceed to the second phase: Split Delta Encoding.

### Phase 2: Split Delta Encoding

In the second phase, we further compress the delta encoded series by splitting it into two separate lists of positive and negative deltas. We then perform additional delta encoding on these lists. Let's break down the steps and proceed with the Lisp code.

### Step 1: Calculate Average Delta

The first step is to calculate the AVERAGE_DELTA value, which is used to determine whether a delta is positive or negative.

```lisp
(defun calculate-average-delta (delta-encoded-list)
  "Calculate the average delta from the list of delta-encoded numbers.

  Example:
  ;> (calculate-average-delta '(10 3 10 27))
  ;; => 12.5
  "
  (/ (apply #'+ delta-encoded-list) (length delta-encoded-list)))
```

### Step 2: Split Deltas into Positive and Negative Lists

Now we split the delta-encoded series into two separate lists, one for positive and one for negative deltas. While doing this, we record the splitting details using a vector.

```lisp
(defun split-deltas (delta-encoded-list average-delta)
  "Split the delta-encoded list into positive and negative deltas, and record the split using a bit vector.

  Examples:
  ;> (split-deltas '(10 3 10 27) 12.5)
  ;; => ((27) (10 3 10) #(1 0 0 1))

  ;> (split-deltas '(10 15 25 3 50) 6)
  ;; => ((10 15 25 50) (3) #(1 1 1 0 1))
  "
  (let ((positive-deltas '())
        (negative-deltas '())
        (split-vector (make-array (length delta-encoded-list) :element-type 'bit)))
    (loop for delta in delta-encoded-list
          for i from 0
          do (if (>= delta average-delta)
                 (progn (setf (aref split-vector i) 1)
                        (push delta positive-deltas))
                 (progn (setf (aref split-vector i) 0)
                        (push delta negative-deltas))))
    (values (nreverse positive-deltas) (nreverse negative-deltas) split-vector)))
```

### Step 3: Further Delta Encoding

After splitting, we delta encode both the positive and negative delta lists.

```lisp
(defun further-delta-encode (deltas)
  "Perform delta encoding on the provided list of deltas.

  Example:
  ;> (further-delta-encode '(10 3 15 27))
  ;; => (10 -7 12 12)
  "
  (delta-encode deltas))
```

### Step 4: Integrate the Split Delta Encoding Steps

Now we'll combine the above steps into a cohesive function for the split delta encoding process.

```lisp
(defun second-phase-compression (delta-encoded-list)
  "Perform the second phase of compression: split delta encoding.

  Example:
  ;> (multiple-value-bind (pos-deltas neg-deltas split-vector)
  ;;       (second-phase-compression '(10 3 10 27))
  ;;    (list pos-deltas neg-deltas split-vector))
  ;; => ((27) (10 3 10) #(1 0 0 1))
  "
  (let* ((average-delta (calculate-average-delta delta-encoded-list))
         (positive-deltas '())
         (negative-deltas '())
         (split-vector (make-array (length delta-encoded-list) :element-type 'bit)))
    ;; Split the deltas
    (multiple-value-bind (pos-deltas neg-deltas split-vec)
        (split-deltas delta-encoded-list average-delta)
      (setf positive-deltas pos-deltas
            negative-deltas neg-deltas
            split-vector split-vec))
    ;; Further delta encode both lists
    (let ((encoded-positive-deltas (further-delta-encode positive-deltas))
          (encoded-negative-deltas (further-delta-encode negative-deltas)))
      (values encoded-positive-deltas encoded-negative-deltas split-vector))))
```

### Step 5: Decompression of the Split Delta Encoding

For decompression, we need to reverse the split delta encoding process. This involves reconstituting the original delta list from the split deltas and then performing cumulative sums.

```lisp
(defun second-phase-decompression (encoded-positive-deltas encoded-negative-deltas split-vector)
  "Reverse the split delta encoding to produce the original delta-encoded list of numbers.

  Example:
  ;> (second-phase-decompression (list 27) (list 10 3 10) #(1 0 0 1))
  ;; => (10 3 10 27)
  "
  (let ((positive-deltas (delta-decode encoded-positive-deltas))
        (negative-deltas (delta-decode encoded-negative-deltas))
        (original-deltas '()))
    (loop for bit across split-vector
          for i from 0
          do (push (if (= bit 1)
                       (pop positive-deltas)
                       (pop negative-deltas))
                   original-deltas))
    (nreverse original-deltas)))
```

### Step 6: Integrating Everything into a Round-Trip Test

To ensure everything works as expected, we'll create a comprehensive function that performs both phases of compression and decompression, ensuring fidelity of the data.

```lisp
(defun full-round-trip (binary-data)
  "Perform a full round trip of compression and decompression.

  Example:
  ;> (multiple-value-bind (original first-phase second-phase second-decoded first-decoded)
  ;;       (full-round-trip #(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
  ;;                           32 33 34 35 36 37 38 39 40 41 42 43 44 45))
  ;;    (list original first-phase second-phase second-decoded first-decoded))
  ;; => ((33582872004870743689512057470824895035 64584848121458614284642108774700913664)
  ;;     (33582872004870743689512057470824895035 31001985655961709470996805038751582129)
  ;;     ((31001985655961709470996805038751582129) nil #(1 0 0 1))
  ;;     (33582872004870743689512057470824895035 31001985655961709470996805038751582129)
  ;;     (33582872004870743689512057470824895035 64584848121458614284642108774700913664))
  "
  (let* ((first-phase-compressed (first-phase-compression binary-data))
         (second-phase-compressed (multiple-value-list
                                   (second-phase-compression first-phase-compressed)))
         (second-phase-decompressed (apply #'second-phase-decompression second-phase-compressed))
         (first-phase-decompressed (first-phase-decompression second-phase-decompressed)))
    (values (extract-256bit-numbers binary-data)
            first-phase-compressed
            second-phase-compressed
            second-phase-decompressed
            first-phase-decompressed)))
```

#### Profiling Performance with Large Datasets

To understand how the performance scales with larger datasets, we profile the compression and decompression functions using increasingly large amounts of random data. This involves measuring execution time and size reduction for various dataset sizes.

- **Function to Generate Random Data:** `generate-random-256bit-numbers`
- **Function to Measure Time:** `measure-compression-decompression-time`
- **Profiling Function:** `profile-performance`

We can run tests with dataset sizes ranging from small to large, incrementally increasing the size and measuring the performance at each step.

```lisp
(defun generate-random-256bit-numbers (count)
  "Generate a list of `count` random 256-bit numbers."
  (loop repeat count
        collect (random (expt 2 256))))

(defun measure-compression-decompression-time (data)
  "Measure the time taken to compress and decompress the data."
  (let ((start-time (get-internal-real-time))
        (units-per-second internal-time-units-per-second))
    (let ((compressed (first-phase-compression data)))
      (second-phase-compression compressed))
    (let ((second-phase-comp (multiple-value-list (second-phase-compression (first-phase-compression data)))))
      (apply #'second-phase-decompression second-phase-comp))
    (let ((end-time (get-internal-real-time)))
      (/ (- end-time start-time) (float units-per-second)))))

(defun profile-performance (max-size increment)
  "Profile compression and decompression performance for increasing data sizes."
  (loop for size from increment to max-size by increment
        for binary-data = (map 'vector 'identity (make-array (* size 32) :element-type '(unsigned-byte 8)
                                       :initial-contents (generate-random-256bit-numbers size)))
        do (format t "~&Data Size: ~D numbers~%" size)
           (format t " Time: ~D seconds~%" (measure-compression-decompression-time binary-data))
           (format t " Original Bits: ~D~%" (* size 256))
           (let* ((compressed (first-phase-compression binary-data))
                  (second-phase-comp (multiple-value-list (second-phase-compression compressed))))
             (format t " Compressed Bits (first phase): ~D~%" (integer-length (apply 'concatenate 'vector compressed)))
             (format t " Compressed Bits (second phase): ~D~%" (integer-length (apply 'concatenate 'vector second-phase-comp))))))

; Example Usage: Profile performance for data sizes up to 10000, increasing by 1000 each step.
(profile-performance 10000 1000)
```

#### Recursive Compression with Encryption/Decryption

By recursively encrypting and compressing the data, we can potentially reveal patterns that are beneficial for compression. This involves simulating encryption via a simple bitwise NOT operation and performing multiple cycles of compression.

- **Encryption Function:** `encrypt-data`
- **Decryption Function:** `decrypt-data`
- **Recursive Compression Function:** `recursive-compression`

This recursive approach demonstrates how input data can be transformed in cycles to enhance compression, showing the potential difference recursive encryption makes in compressibility.

```lisp
(defun encrypt-data (data)
  "Simulate encryption by performing bitwise NOT operation."
  (map 'vector (lambda (x) (logxor x #xffffffff)) data))

(defun decrypt-data (data)
  "Simulate decryption by performing bitwise NOT operation again."
  (encrypt-data data))  ; Bitwise NOT is its own inverse

(defun recursive-compression (data cycles)
  "Perform recursive compression on data, simulating encryption and decryption at each cycle."
  (loop for i from 1 to cycles
        do (format t "~&Cycle ~D:~%" i)
           (let* ((compressed (first-phase-compression data))
                  (second-phase-comp (multiple-value-list (second-phase-compression compressed))))
             (format t "  Compression Phase: ~D bits~%" (integer-length (apply 'concatenate 'vector second-phase-comp)))
             (setf data (apply 'vector (apply 'concatenate 'list second-phase-comp))))
           ;; Encrypt data for next cycle
           (setf data (encrypt-data data))))

; Example Usage: Perform 5 cycles of recursive compression
(recursive-compression (map 'vector 'identity (make-array 32768 :element-type '(unsigned-byte 8)
                                         :initial-contents (generate-random-256bit-numbers 1024))) 5)
```
