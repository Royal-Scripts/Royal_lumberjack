let audioPlayer = null;

window.addEventListener('message', function(event) {
    const d = event.data;
    if (d.action === "openUI") {
        document.getElementById('container').style.display = 'flex';
        updateLeaderboard(d.leaderboard);
        updateShop(d.shopItems);
        updateJobButton(d.onDuty);
        switchTab('dashboard');
    } else if (d.action === "updateOnDuty") {
        updateJobButton(d.state);
        toggleHUD(d.state);
    } else if (d.action === "updateAxe") {
        updateAxeHUD(d.remaining);
    } else if (d.action === "playSound") {
        playCustomSound(d.file, d.volume, d.loop);
    } else if (d.action === "stopSound") {
        stopCustomSound();
    }
});

function toggleHUD(state) {
    const hud = document.getElementById('job-hud');
    if (state) {
        hud.classList.remove('hidden');
        hud.style.display = 'block';
    } else {
        hud.classList.add('hidden');
        hud.style.display = 'none';
    }
}

function updateAxeHUD(remaining) {
    const axeText = document.getElementById('axe-durability');
    axeText.innerText = `${remaining} / 20`;
    if (remaining <= 5) {
        axeText.classList.add('text-red-500');
        axeText.classList.remove('text-white');
    } else {
        axeText.classList.remove('text-red-500');
        axeText.classList.add('text-white');
    }
}

function switchTab(tab) {
    const sections = ['dashboard', 'shop', 'info'];
    sections.forEach(s => {
        document.getElementById(`section-${s}`).classList.add('hidden');
        document.getElementById(`tab-${s}`).classList.remove('active');
    });
    document.getElementById(`section-${tab}`).classList.remove('hidden');
    document.getElementById(`tab-${tab}`).classList.add('active');
}

function updateShop(items) {
    const list = document.getElementById('shop-items-list');
    if (!items) return;
    list.innerHTML = items.map((item, index) => {
        const imgSrc = `nui://ox_inventory/web/images/${item.item}.png`;
        return `
            <div class="leaderboard-item p-6 rounded-3xl flex items-center justify-between group hover:border-cyan-500/50 transition-all border border-white/5">
                <div class="flex items-center gap-6">
                    <div class="w-20 h-20 bg-black/40 rounded-2xl flex items-center justify-center border border-white/10 overflow-hidden relative">
                        <img src="${imgSrc}" class="w-14 h-14 object-contain" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
                        <div class="hidden absolute inset-0 items-center justify-center"><i class="${item.icon} text-3xl text-cyan-400/50"></i></div>
                    </div>
                    <div>
                        <h4 class="text-white font-black text-lg text-sharp">${item.label}</h4>
                        <p class="text-[11px] text-white/60 font-bold uppercase tracking-wider">${item.description}</p>
                    </div>
                </div>
                <button onclick="buyItem(${index + 1})" class="px-8 py-3 bg-cyan-500/20 border border-cyan-500/50 hover:bg-cyan-500 text-white font-black text-sm rounded-2xl transition-all shadow-lg active:scale-90">
                    $${item.price}
                </button>
            </div>
        `;
    }).join('');
}

function buyItem(index) {
    fetch(`https://${GetParentResourceName()}/buyItem`, { 
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ index: index })
    });
}

function updateJobButton(onDuty) {
    const btn = document.getElementById('job-toggle-btn');
    if (onDuty) {
        btn.innerText = "FINISH WORK";
        btn.className = "w-full py-6 rounded-3xl btn-work text-lg text-white shadow-2xl on-duty";
    } else {
        btn.innerText = "START SHIFT";
        btn.className = "w-full py-6 rounded-3xl btn-work text-lg text-white shadow-2xl off-duty";
    }
}

function updateLeaderboard(lb) {
    const list = document.getElementById('leaderboard-list');
    list.innerHTML = lb.map((e, i) => `
        <li class="flex justify-between items-center p-5 leaderboard-item rounded-2xl">
            <div class="flex items-center gap-5">
                <span class="text-xs font-black bg-cyan-500/20 w-8 h-8 flex items-center justify-center rounded-lg text-cyan-400 border border-cyan-500/20">#${i+1}</span>
                <span class="text-sm font-bold text-white text-sharp">${e.name}</span>
            </div>
            <span class="text-sm font-black text-cyan-400 text-sharp">${e.wood_collected} <small class="text-[9px] text-white/40 uppercase tracking-widest ml-1">LOGS</small></span>
        </li>
    `).join('');
}

function playCustomSound(fileName, volume, loop) {
    if (audioPlayer) { audioPlayer.pause(); audioPlayer = null; }
    audioPlayer = new Audio(`./sound/${fileName}.mp3`);
    audioPlayer.volume = volume || 0.5;
    audioPlayer.loop = loop || false;
    audioPlayer.play().catch(e => {});
}

function stopCustomSound() { if (audioPlayer) { audioPlayer.pause(); audioPlayer = null; } }
function toggleJob() { fetch(`https://${GetParentResourceName()}/toggleJob`, { method: 'POST' }); }
function closeUI() { document.getElementById('container').style.display = 'none'; fetch(`https://${GetParentResourceName()}/close`, { method: 'POST' }); }
window.addEventListener('keydown', function(event) { if (event.key === 'Escape') closeUI(); });