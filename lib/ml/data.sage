# Data loading and batching utilities for ML training

# ============================================================================
# Dataset
# ============================================================================

# Create a dataset from feature and label tensors
proc create_dataset(features, labels):
    let ds = {}
    ds["features"] = features
    ds["labels"] = labels
    if features["ndim"] == 2:
        ds["num_samples"] = features["shape"][0]
    else:
        ds["num_samples"] = 1
    ds["feature_dim"] = features["shape"][features["ndim"] - 1]
    return ds

# Get a single sample from dataset
proc get_sample(ds, idx):
    let feat_dim = ds["feature_dim"]
    let sample = {}
    let f_data = []
    for j in range(feat_dim):
        push(f_data, ds["features"]["data"][idx * feat_dim + j])
    sample["features"] = {}
    sample["features"]["data"] = f_data
    sample["features"]["shape"] = [feat_dim]
    sample["features"]["size"] = feat_dim
    sample["features"]["ndim"] = 1
    sample["features"]["requires_grad"] = false
    sample["features"]["grad"] = nil
    sample["features"]["_grad_fn"] = nil
    sample["label"] = ds["labels"]["data"][idx]
    return sample

# ============================================================================
# DataLoader (batching)
# ============================================================================

proc create_loader(dataset, batch_size, shuffle_data):
    let loader = {}
    loader["dataset"] = dataset
    loader["batch_size"] = batch_size
    loader["shuffle"] = shuffle_data
    loader["num_samples"] = dataset["num_samples"]
    loader["num_batches"] = ((dataset["num_samples"] + batch_size - 1) / batch_size) | 0
    # Create index array
    let indices = []
    for i in range(dataset["num_samples"]):
        push(indices, i)
    loader["indices"] = indices
    return loader

# Shuffle the loader indices
proc shuffle_indices(loader, rng_state):
    let indices = loader["indices"]
    let n = len(indices)
    let i = n - 1
    while i > 0:
        rng_state["v"] = (rng_state["v"] * 1664525 + 1013904223) & 4294967295
        let j = rng_state["v"] - ((rng_state["v"] / (i + 1)) | 0) * (i + 1)
        let temp = indices[i]
        indices[i] = indices[j]
        indices[j] = temp
        i = i - 1

# Get a batch of data
proc get_batch(loader, batch_idx):
    let ds = loader["dataset"]
    let bs = loader["batch_size"]
    let start = batch_idx * bs
    let end_idx = start + bs
    if end_idx > loader["num_samples"]:
        end_idx = loader["num_samples"]
    let actual_bs = end_idx - start
    let feat_dim = ds["feature_dim"]
    let f_data = []
    let l_data = []
    for i in range(actual_bs):
        let idx = loader["indices"][start + i]
        for j in range(feat_dim):
            push(f_data, ds["features"]["data"][idx * feat_dim + j])
        push(l_data, ds["labels"]["data"][idx])
    let batch = {}
    batch["features"] = {}
    batch["features"]["data"] = f_data
    batch["features"]["shape"] = [actual_bs, feat_dim]
    batch["features"]["size"] = actual_bs * feat_dim
    batch["features"]["ndim"] = 2
    batch["features"]["requires_grad"] = false
    batch["features"]["grad"] = nil
    batch["features"]["_grad_fn"] = nil
    batch["labels"] = {}
    batch["labels"]["data"] = l_data
    batch["labels"]["shape"] = [actual_bs]
    batch["labels"]["size"] = actual_bs
    batch["labels"]["ndim"] = 1
    batch["labels"]["requires_grad"] = false
    batch["labels"]["grad"] = nil
    batch["labels"]["_grad_fn"] = nil
    batch["batch_size"] = actual_bs
    return batch

# ============================================================================
# Data preprocessing
# ============================================================================

# Normalize features to zero mean, unit variance
proc normalize(features):
    let n = features["shape"][0]
    let d = features["shape"][1]
    let data = features["data"]
    # Compute mean and std per feature
    for j in range(d):
        let s = 0
        for i in range(n):
            s = s + data[i * d + j]
        let mu = s / n
        let var_sum = 0
        for i in range(n):
            let diff = data[i * d + j] - mu
            var_sum = var_sum + diff * diff
        import math
        let std = math.sqrt(var_sum / n)
        if std < 0.00001:
            std = 0.00001
        for i in range(n):
            data[i * d + j] = (data[i * d + j] - mu) / std
    return features

# Min-max scale features to [0, 1]
proc min_max_scale(features):
    let n = features["shape"][0]
    let d = features["shape"][1]
    let data = features["data"]
    for j in range(d):
        let lo = data[j]
        let hi = data[j]
        for i in range(n):
            let v = data[i * d + j]
            if v < lo:
                lo = v
            if v > hi:
                hi = v
        let rng = hi - lo
        if rng < 0.00001:
            rng = 0.00001
        for i in range(n):
            data[i * d + j] = (data[i * d + j] - lo) / rng
    return features

# One-hot encode labels
proc one_hot(labels, num_classes):
    let n = labels["size"]
    let data = []
    for i in range(n):
        let cls = labels["data"][i]
        for j in range(num_classes):
            if j == cls:
                push(data, 1)
            else:
                push(data, 0)
    let result = {}
    result["data"] = data
    result["shape"] = [n, num_classes]
    result["size"] = n * num_classes
    result["ndim"] = 2
    result["requires_grad"] = false
    result["grad"] = nil
    result["_grad_fn"] = nil
    return result

# Train/test split
proc train_test_split(dataset, test_ratio):
    let n = dataset["num_samples"]
    let test_n = (n * test_ratio) | 0
    let train_n = n - test_n
    let feat_dim = dataset["feature_dim"]
    let train_f = []
    let train_l = []
    let test_f = []
    let test_l = []
    for i in range(train_n):
        for j in range(feat_dim):
            push(train_f, dataset["features"]["data"][i * feat_dim + j])
        push(train_l, dataset["labels"]["data"][i])
    for i in range(test_n):
        let idx = train_n + i
        for j in range(feat_dim):
            push(test_f, dataset["features"]["data"][idx * feat_dim + j])
        push(test_l, dataset["labels"]["data"][idx])
    let result = {}
    let train_feat = {}
    train_feat["data"] = train_f
    train_feat["shape"] = [train_n, feat_dim]
    train_feat["size"] = train_n * feat_dim
    train_feat["ndim"] = 2
    train_feat["requires_grad"] = false
    train_feat["grad"] = nil
    train_feat["_grad_fn"] = nil
    let train_lab = {}
    train_lab["data"] = train_l
    train_lab["shape"] = [train_n]
    train_lab["size"] = train_n
    train_lab["ndim"] = 1
    train_lab["requires_grad"] = false
    train_lab["grad"] = nil
    train_lab["_grad_fn"] = nil
    result["train"] = create_dataset(train_feat, train_lab)
    let test_feat = {}
    test_feat["data"] = test_f
    test_feat["shape"] = [test_n, feat_dim]
    test_feat["size"] = test_n * feat_dim
    test_feat["ndim"] = 2
    test_feat["requires_grad"] = false
    test_feat["grad"] = nil
    test_feat["_grad_fn"] = nil
    let test_lab = {}
    test_lab["data"] = test_l
    test_lab["shape"] = [test_n]
    test_lab["size"] = test_n
    test_lab["ndim"] = 1
    test_lab["requires_grad"] = false
    test_lab["grad"] = nil
    test_lab["_grad_fn"] = nil
    result["test"] = create_dataset(test_feat, test_lab)
    return result
