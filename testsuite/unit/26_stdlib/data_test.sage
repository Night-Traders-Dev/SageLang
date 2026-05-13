gc_disable()
# EXPECT: 4
# EXPECT: 2
# EXPECT: 2
# EXPECT: 2

import ml.data
import ml.tensor

# Create dataset
let features = tensor.from_flat([1, 2, 3, 4, 5, 6, 7, 8], [4, 2])
let labels = tensor.from_flat([0, 1, 0, 1], [4])
let ds = data.create_dataset(features, labels)
print ds["num_samples"]
print ds["feature_dim"]

# DataLoader
let loader = data.create_loader(ds, 2, false)
print loader["num_batches"]

# Get batch
let batch = data.get_batch(loader, 0)
print batch["batch_size"]
