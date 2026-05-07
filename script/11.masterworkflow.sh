#!/bin/bash

# --- Cấu hình thư mục ---
WORKDIR="/mnt/10T/huyha/precisiongene/suran_sal"
SCRIPT_DIR="$WORKDIR/script"
RESULT_DIR="$WORKDIR/result"
LOG_DIR="$SCRIPT_DIR/slurm_logs"

mkdir -p "$LOG_DIR"

echo "====================================================="
echo "  PRECISIONGENE PIPELINE - AUTO SUBMIT & RESUME      "
echo "====================================================="

# --- Hàm Submit Job thông minh ---
# Cú pháp: submit_job <Tên_bước> <File_script> <File/Thư_mục_kỳ_vọng> <Job_ID_phụ_thuộc>
submit_job() {
    local step_name="$1"
    local script_file="$2"
    local target_out="$3"
    local dep_job_id="$4"

    local is_done=0

    # Kiểm tra xem output đã tồn tại chưa (Resume Logic)
    if [[ -f "$target_out" && -s "$target_out" ]]; then
        # Nếu là file và dung lượng > 0
        is_done=1
    elif [[ -d "$target_out" && "$(ls -A "$target_out" 2>/dev/null)" ]]; then
        # Nếu là thư mục và có chứa dữ liệu bên trong
        is_done=1
    fi

    if [[ $is_done -eq 1 ]]; then
        echo "[SKIP] $step_name: Output already exists -> $target_out" >&2
        echo "DONE" # Trả về keyword DONE thay vì Job ID
    else
        local sbatch_args="--parsable"
        
        # Nếu có job phụ thuộc và job đó chưa DONE, thêm dependency
        if [[ -n "$dep_job_id" && "$dep_job_id" != "DONE" ]]; then
            sbatch_args="$sbatch_args --dependency=afterok:$dep_job_id"
        fi
        
        # Gửi script cho SLURM
        local job_id=$(sbatch $sbatch_args "$script_file")
        echo "[SUBMIT] $step_name: JobID $job_id" >&2
        echo "$job_id"
    fi
}

# --- THỰC THI PIPELINE ---
# Lưu ý: Em hãy điều chỉnh lại đường dẫn "target_out" (cột số 3) cho khớp chính xác 
# với file kết quả cuối cùng mà mỗi script của em sinh ra để Resume hoạt động chuẩn nhất.

# 1. Fastp
JOB1=$(submit_job "Fastp" "$SCRIPT_DIR/1.fastp.sh" "$RESULT_DIR/fastp" "")

# 2. BBDuk
JOB2=$(submit_job "BBDuk" "$SCRIPT_DIR/2.bbduk.sh" "$RESULT_DIR/bbduk" "$JOB1")

# 3. Megahit (Kiểm tra file contigs cuối cùng)
JOB3=$(submit_job "Megahit" "$SCRIPT_DIR/3.megahit.sh" "$RESULT_DIR/megahit/final.contigs.fa" "$JOB2")

# 4. Pilon
JOB4=$(submit_job "Pilon" "$SCRIPT_DIR/4.pilon.sh" "$RESULT_DIR/pilon/pilon.fasta" "$JOB3")

# 5. SSpaces
JOB5=$(submit_job "SSpaces" "$SCRIPT_DIR/5.sspaces.sh" "$RESULT_DIR/sspaces" "$JOB4")

# 6. Pilon SS (Lần 2)
JOB6=$(submit_job "Pilon_SS" "$SCRIPT_DIR/6.pilon_ss.sh" "$RESULT_DIR/pilon_ss" "$JOB5")

# --- Các bước sau Assembly có thể chạy song song ---

# 7. Bakta (Phụ thuộc vào Job 6)
JOB7=$(submit_job "Bakta" "$SCRIPT_DIR/7.bakta.sh" "$RESULT_DIR/bakta" "$JOB6")

# 8. CheckM (Phụ thuộc vào Job 6)
JOB8=$(submit_job "CheckM" "$SCRIPT_DIR/8.checkm_GTDB_wgs.sh" "$RESULT_DIR/checkm" "$JOB6")

# 9. EggNOG (Phụ thuộc vào Job 7 - Bakta)
JOB9=$(submit_job "EggNOG" "$SCRIPT_DIR/9.eggnog.sh" "$RESULT_DIR/eggnog" "$JOB7")

# 10. BUSCO (Phụ thuộc vào Job 6)
JOB10=$(submit_job "BUSCO" "$SCRIPT_DIR/10.busco.sh" "$RESULT_DIR/busco" "$JOB6")



echo "====================================================="
echo "Pipeline execution check complete!"
echo "Sử dụng lệnh 'squeue -u \$USER' để theo dõi các job đang chạy."