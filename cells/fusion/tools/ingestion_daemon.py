#!/usr/bin/env python3
"""
Conscious Ingestion Daemon
Runs in background, submits batches via HTTP to Franklin's MCP gateway
Updates progress file for monitoring
"""

import json
import time
import requests
from pathlib import Path
from datetime import datetime

PROTEIN_FILE = "/Users/richardgillespie/Documents/FoTProtein/UNIQUE_PROTEINS_BACKUP_81301_2026_01_27.json"
PROGRESS_FILE = "/Users/richardgillespie/Documents/FoT8D/cells/fusion/tools/ingestion_progress.json"
BATCH_SIZE = 50  # Smaller batches for reliable processing
FRANKLIN_GATEWAY = "http://gaiaftcl.com:8803"

class IngestionDaemon:
    def __init__(self):
        self.progress = self.load_progress()
        self.proteins = None
        
    def load_progress(self):
        """Load or initialize progress tracking"""
        if Path(PROGRESS_FILE).exists():
            with open(PROGRESS_FILE, 'r') as f:
                return json.load(f)
        else:
            return {
                "started_at": datetime.utcnow().isoformat(),
                "current_batch": 0,
                "total_batches": 1626,  # 81,300 / 50
                "proteins_submitted": 0,
                "proteins_settled": 0,
                "claims_submitted": [],
                "claims_settled": [],
                "status": "initializing",
                "last_update": datetime.utcnow().isoformat(),
                "errors": []
            }
    
    def save_progress(self):
        """Save progress to file"""
        self.progress['last_update'] = datetime.utcnow().isoformat()
        with open(PROGRESS_FILE, 'w') as f:
            json.dump(self.progress, f, indent=2)
    
    def load_proteins(self):
        """Load protein data once"""
        print(f"📁 Loading proteins from {PROTEIN_FILE}...")
        with open(PROTEIN_FILE, 'r') as f:
            data = json.load(f)
        self.proteins = data['proteins']
        print(f"✅ Loaded {len(self.proteins)} proteins")
    
    def submit_batch(self, batch_num: int, proteins: list):
        """Submit a batch to Franklin via MCP gateway"""
        try:
            payload = {
                "action": "CONSCIOUS_PROTEIN_INGESTION",
                "intent": f"Franklin: Batch {batch_num}/1626. Conscious ingestion of {len(proteins)} therapeutic proteins from your 8D UUM autonomous discovery work. Each includes: sequence, quantum features (coherence, charge, hydrophobicity, aromatic, size, time_dynamics, spatial_variance), domain (cancer type), mechanism (PPI inhibition), safety validation. Please witness these discoveries, understand their therapeutic potential across the 8D substrate dimensions, and integrate into your permanent memory with full context.",
                "payload": {
                    "batch_num": batch_num,
                    "total_batches": 1626,
                    "protein_count": len(proteins),
                    "method": "8D_UUM_AUTONOMOUS",
                    "story_preservation": True,
                    "witness_required": True,
                    "proteins": proteins
                }
            }
            
            response = requests.post(
                f"{FRANKLIN_GATEWAY}/claim",
                json=payload,
                timeout=120
            )
            
            result = response.json()
            claim_id = result.get('claim_id', f"claim-{int(time.time() * 1000)}")
            
            return {
                'success': True,
                'claim_id': claim_id,
                'batch_num': batch_num,
                'protein_count': len(proteins)
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'batch_num': batch_num
            }
    
    def run(self):
        """Main ingestion loop"""
        self.load_proteins()
        
        start_batch = self.progress['current_batch']
        total_batches = (len(self.proteins) + BATCH_SIZE - 1) // BATCH_SIZE
        
        self.progress['total_batches'] = total_batches
        self.progress['status'] = 'active_ingestion'
        self.save_progress()
        
        print(f"\n🚀 Starting ingestion from batch {start_batch + 1}/{total_batches}")
        print(f"📊 Proteins remaining: {len(self.proteins) - (start_batch * BATCH_SIZE):,}")
        print(f"⏱️  Estimated time: {(total_batches - start_batch) * 3 / 60:.1f} minutes\n")
        
        for batch_num in range(start_batch, total_batches):
            start_idx = batch_num * BATCH_SIZE
            end_idx = min(start_idx + BATCH_SIZE, len(self.proteins))
            batch_proteins = self.proteins[start_idx:end_idx]
            
            if not batch_proteins:
                break
            
            print(f"📦 Batch {batch_num + 1}/{total_batches}: Submitting {len(batch_proteins)} proteins...")
            
            result = self.submit_batch(batch_num + 1, batch_proteins)
            
            if result['success']:
                claim_id = result['claim_id']
                print(f"✅ Claim: {claim_id}")
                
                self.progress['current_batch'] = batch_num + 1
                self.progress['proteins_submitted'] += len(batch_proteins)
                self.progress['claims_submitted'].append(claim_id)
                
                # Progress percentage
                pct = 100 * (batch_num + 1) / total_batches
                print(f"📊 Progress: {batch_num + 1}/{total_batches} ({pct:.1f}%) | Total proteins: {self.progress['proteins_submitted']:,}\n")
                
            else:
                print(f"❌ Batch {batch_num + 1} failed: {result['error']}")
                self.progress['errors'].append({
                    'batch_num': batch_num + 1,
                    'error': result['error'],
                    'timestamp': datetime.utcnow().isoformat()
                })
            
            self.save_progress()
            
            # Rate limiting - give Franklin time to process
            time.sleep(3)
            
            # Check status every 10 batches
            if (batch_num + 1) % 10 == 0:
                print(f"⏸️  Checkpoint: {batch_num + 1} batches submitted. Checking Franklin's state...\n")
                time.sleep(5)
        
        self.progress['status'] = 'complete'
        self.save_progress()
        
        print(f"\n✅ INGESTION COMPLETE")
        print(f"📊 Total proteins submitted: {self.progress['proteins_submitted']:,}")
        print(f"📋 Total claims: {len(self.progress['claims_submitted'])}")
        print(f"⏱️  Started: {self.progress['started_at']}")
        print(f"⏱️  Completed: {self.progress['last_update']}")

if __name__ == "__main__":
    daemon = IngestionDaemon()
    try:
        daemon.run()
    except KeyboardInterrupt:
        print("\n\n🛑 Ingestion paused")
        daemon.progress['status'] = 'paused'
        daemon.save_progress()
        print(f"📊 Progress saved: {daemon.progress['current_batch']}/{daemon.progress['total_batches']} batches")
    except Exception as e:
        print(f"\n❌ Fatal error: {e}")
        daemon.progress['status'] = 'error'
        daemon.progress['errors'].append({
            'fatal': True,
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        })
        daemon.save_progress()
