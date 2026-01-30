import os
import time
import subprocess
import platform
import argparse
from datetime import datetime, timezone

import polars as pl


STORAGE_DRIVE = "/"  # Root directory for storage metrics


def get_cpu_usage():
    if platform.system() == "Darwin":
        # macOS
        try:
            output = subprocess.check_output(["top", "-l", "1", "-n", "0"]).decode()
            for line in output.split('\n'):
                if "CPU usage:" in line:
                    # Example: "CPU usage: 10.55% user, 8.24% sys, 81.20% idle"
                    parts = line.split()
                    user = float(parts[2].strip('%'))
                    sys = float(parts[4].strip('%'))
                    return user + sys
        except:
            pass
    elif platform.system() == "Linux":
        # Linux
        try:
            with open("/proc/stat", "r") as f:
                line1 = f.readline()
            time.sleep(0.5)
            with open("/proc/stat", "r") as f:
                line2 = f.readline()
            
            def get_times(line):
                parts = line.split()
                # user nice system idle iowait irq softirq
                times = [float(x) for x in parts[1:8]]
                idle = times[3]
                total = sum(times)
                return idle, total

            idle1, total1 = get_times(line1)
            idle2, total2 = get_times(line2)
            
            idle_delta = idle2 - idle1
            total_delta = total2 - total1
            
            if total_delta > 0:
                return 100.0 * (1.0 - idle_delta / total_delta)
        except:
            pass
    return 0.0


def get_memory_metrics():
    metrics = {"MemoryTotalBytes": 0, "MemoryUsedBytes": 0}
    if platform.system() == "Darwin":
        # macOS
        try:
            total = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"]).decode().strip())
            vm_stat = subprocess.check_output(["vm_stat"]).decode()
            free_pages = 0
            for line in vm_stat.split('\n'):
                if "Pages free:" in line:
                    free_pages = int(line.split()[-1].strip('.'))
                    break
            metrics["MemoryTotalBytes"] = total
            metrics["MemoryUsedBytes"] = total - (free_pages * 4096)
        except:
            pass
    elif platform.system() == "Linux":
        # Linux
        try:
            with open("/proc/meminfo", "r") as f:
                meminfo = {}
                for line in f:
                    parts = line.split()
                    if len(parts) >= 2:
                        meminfo[parts[0].strip(':')] = int(parts[1]) * 1024
            
            total = meminfo.get("MemTotal", 0)
            free = meminfo.get("MemFree", 0)
            buffers = meminfo.get("Buffers", 0)
            cached = meminfo.get("Cached", 0)
            metrics["MemoryTotalBytes"] = total
            metrics["MemoryUsedBytes"] = total - free - buffers - cached
        except:
            pass
    return metrics


def get_network_metrics():
    metrics = {"NetworkInTotalBytes": 0, "NetworkOutTotalBytes": 0}
    if platform.system() == "Darwin":
        # macOS
        try:
            output = subprocess.check_output(["netstat", "-ibn"]).decode()
            lines = output.split('\n')[1:]
            for line in lines:
                parts = line.split()
                if len(parts) >= 10 and not parts[0].startswith("lo"):
                    try:
                        metrics["NetworkInTotalBytes"] += int(parts[6])
                        metrics["NetworkOutTotalBytes"] += int(parts[9])
                    except:
                        continue
        except:
            pass
    elif platform.system() == "Linux":
        # Linux
        try:
            with open("/proc/net/dev", "r") as f:
                lines = f.readlines()[2:]
                for line in lines:
                    parts = line.split()
                    if len(parts) >= 10 and not parts[0].startswith("lo"):
                        metrics["NetworkInTotalBytes"] += int(parts[1])
                        metrics["NetworkOutTotalBytes"] += int(parts[9])
        except:
            pass
    return metrics


def get_storage_metrics():
    metrics = {"StorageTotalBytes": 0, "StorageUsedBytes": 0}
    try:
        # Cross-platform way using os.statvfs (Linux/macOS)
        st = os.statvfs(STORAGE_DRIVE)
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        metrics["StorageTotalBytes"] = total
        metrics["StorageUsedBytes"] = total - free
    except:
        pass
    return metrics


def get_parquet_path(output_dir: str, date: datetime) -> str:
    """Get the parquet file path for a given date."""
    date_str = date.strftime("%Y-%m-%d")
    return os.path.join(output_dir, f"metrics_{date_str}.parquet")


def append_metrics_to_parquet(output_dir: str, metrics: dict):
    """Append a single metrics record to the day's parquet file."""
    timestamp = datetime.fromisoformat(metrics["Timestamp"].replace("Z", "+00:00"))
    parquet_path = get_parquet_path(output_dir, timestamp)
    
    # Create a new DataFrame with the single record
    new_df = pl.DataFrame({
        "Timestamp": [timestamp],
        "CpuUsagePercent": [metrics["CpuUsagePercent"]],
        "MemoryTotalBytes": [metrics["MemoryTotalBytes"]],
        "MemoryUsedBytes": [metrics["MemoryUsedBytes"]],
        "NetworkInTotalBytes": [metrics["NetworkInTotalBytes"]],
        "NetworkOutTotalBytes": [metrics["NetworkOutTotalBytes"]],
        "StorageTotalBytes": [metrics["StorageTotalBytes"]],
        "StorageUsedBytes": [metrics["StorageUsedBytes"]],
    })
    
    # If file exists, read and append; otherwise create new
    if os.path.exists(parquet_path):
        existing_df = pl.read_parquet(parquet_path)
        combined_df = pl.concat([existing_df, new_df])
    else:
        combined_df = new_df
    
    # Write back to parquet
    combined_df.write_parquet(parquet_path)


def cleanup_old_files(output_dir: str, max_days: int = 30):
    """Remove parquet files older than max_days."""
    import glob
    from datetime import timedelta
    
    cutoff_date = datetime.now(timezone.utc) - timedelta(days=max_days)
    
    for filepath in glob.glob(os.path.join(output_dir, "metrics_*.parquet")):
        filename = os.path.basename(filepath)
        # Extract date from filename: metrics_YYYY-MM-DD.parquet
        try:
            date_str = filename.replace("metrics_", "").replace(".parquet", "")
            file_date = datetime.strptime(date_str, "%Y-%m-%d").replace(tzinfo=timezone.utc)
            if file_date < cutoff_date:
                os.remove(filepath)
        except ValueError:
            continue


def main():
    parser = argparse.ArgumentParser(description="Collect host metrics and log to parquet files.")
    parser.add_argument("--output-dir", default="./host_metrics", help="Path to the output directory for parquet files.")
    parser.add_argument("--once", action="store_true", help="Run once and exit.")
    parser.add_argument("--max-days", type=int, default=365, help="Maximum number of days to keep.")
    args = parser.parse_args()
    
    # Ensure output directory exists
    os.makedirs(args.output_dir, exist_ok=True)

    while True:
        # Truncate seconds from timestamp since we only update every 60 seconds
        metrics = {
            "Timestamp": time.strftime("%Y-%m-%dT%H:%M:00Z", time.gmtime()),
            "CpuUsagePercent": get_cpu_usage(),
        }
        metrics.update(get_memory_metrics())
        metrics.update(get_network_metrics())
        metrics.update(get_storage_metrics())

        try:
            append_metrics_to_parquet(args.output_dir, metrics)
            
            # Periodically cleanup old files (every hour, check on minute 0)
            if time.gmtime().tm_min == 0:
                cleanup_old_files(args.output_dir, args.max_days)
                    
        except Exception as e:
            print(f"Error writing metrics: {e}")
        
        if args.once:
            break
        time.sleep(60)


if __name__ == "__main__":
    main()
