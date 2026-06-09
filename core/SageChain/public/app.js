async function fetchBlocks() {
    try {
        const response = await fetch('/api/blocks');
        const blocks = await response.json();
        
        const tbody = document.getElementById('blocksTableBody');
        tbody.innerHTML = '';
        
        let totalTxs = 0;
        
        if(blocks.length > 0) {
            document.getElementById('latestBlockHeight').innerText = blocks[0].index;
        }

        blocks.forEach(b => {
            const txCount = b.transactions ? b.transactions.length : 0;
            totalTxs += txCount;
            const date = new Date(b.timestamp * 1000).toLocaleString();
            
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${b.index}</td>
                <td><a class="hash-link" onclick="viewBlock(${b.index})">${b.hash.substring(0, 16)}...${b.hash.substring(b.hash.length-8)}</a></td>
                <td>${txCount}</td>
                <td>${date}</td>
            `;
            tbody.appendChild(tr);
        });
        
        document.getElementById('totalTxs').innerText = totalTxs + '+';
    } catch(err) {
        console.error("Error fetching blocks:", err);
    }
}

async function viewBlock(height) {
    try {
        const res = await fetch(`/api/block?h=${height}`);
        const data = await res.json();
        document.getElementById('modalTitle').innerText = `Block #${height}`;
        document.getElementById('modalData').innerText = JSON.stringify(data, null, 2);
        document.getElementById('blockModal').style.display = "block";
    } catch(err) {
        console.error(err);
    }
}

async function viewTx(hash) {
    try {
        const res = await fetch(`/api/tx?hash=${hash}`);
        const data = await res.json();
        document.getElementById('modalTitle').innerText = `Transaction`;
        document.getElementById('modalData').innerText = JSON.stringify(data, null, 2);
        document.getElementById('blockModal').style.display = "block";
    } catch(err) {
        alert("Not found");
    }
}

async function search() {
    const val = document.getElementById('searchInput').value.trim();
    if (!val) return;
    
    if(!isNaN(val)) {
        viewBlock(val);
    } else {
        viewTx(val);
    }
}

function closeModal() {
    document.getElementById('blockModal').style.display = "none";
}

window.onclick = function(event) {
    const modal = document.getElementById('blockModal');
    if (event.target == modal) {
        modal.style.display = "none";
    }
}

// Initial fetch
fetchBlocks();
// Poll every 5 seconds
setInterval(fetchBlocks, 5000);
