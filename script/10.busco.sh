#!/bin/bash
#SBATCH --job-name=busco
#SBATCH --output=log/busco_%j.out
#SBATCH --error=log/busco_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=120G

# 1. Cấu hình thư mục
BASE_DIR="result/final_polished"
OUT_DIR="result/busco_results"
# Tùy chỉnh file output của script số 8 (CheckM/GTDB) vào đây:
CHECKM_FILE="result/checkm/checkm_summary.txt" 
THREADS=40

mkdir -p "$OUT_DIR"

echo "Starting Automated BUSCO analysis..."
echo "--------------------------------"

# 2. Quét tự động TẤT CẢ các file fasta trong thư mục final_polished
for INPUT_FILE in ${BASE_DIR}/*/*_final_polished.fasta; do
    
    # Lấy tên mẫu từ tên file (ví dụ: BAC1_final_polished.fasta -> BAC1)
    FILENAME=$(basename "$INPUT_FILE")
    SAMPLE="${FILENAME/_final_polished.fasta/}"

    # 3. KIỂM TRA ĐỐI CHIẾU VỚI CHECKM
    # Script chỉ chạy BUSCO nếu mẫu có tồn tại trong file báo cáo của CheckM
    if [[ -f "$CHECKM_FILE" ]]; then
        CHECKM_RESULT=$(grep -w "$SAMPLE" "$CHECKM_FILE")
        
        if [[ -z "$CHECKM_RESULT" ]]; then
            echo "SKIP: $SAMPLE không tìm thấy kết quả trong CheckM. Bỏ qua..."
            continue
        fi
        
        # --- Tùy chọn nâng cao: Chỉ chạy nếu CheckM Completeness > 50% ---
        # Bỏ dấu '#' ở 5 dòng dưới đây nếu em muốn dùng. 
        # Lưu ý: Cần chỉnh '$13' thành đúng số thứ tự cột Completeness trong file text của em.
        #
        COMPLETENESS=$(echo "$CHECKM_RESULT" | awk '{print $13}') 
        C_INT=${COMPLETENESS%.*} # Lấy phần nguyên để so sánh toán học
        if [[ "$C_INT" -lt 50 ]]; then
            echo "SKIP: $SAMPLE bị loại do CheckM Completeness quá thấp ($COMPLETENESS%)."
            continue
        fi
    else
        echo "WARNING: Không tìm thấy file CheckM tổng ($CHECKM_FILE). Mặc định chạy BUSCO..."
    fi

    SAMPLE_OUT_DIR="${OUT_DIR}/${SAMPLE}_busco"
    
    # Vì dùng auto-lineage nên ta dùng wildcard để check file summary
    EXPECTED_SUMMARY_PATTERN="${SAMPLE_OUT_DIR}/short_summary.*.${SAMPLE}_busco.txt"

    # --- 4. CƠ CHẾ RESUME ---
    if ls ${EXPECTED_SUMMARY_PATTERN} 1> /dev/null 2>&1; then
        echo "SKIPPING: $SAMPLE (Phân tích BUSCO đã hoàn thành trước đó)"
    else
        echo "Processing $SAMPLE with --auto-lineage-prok..."

        # 5. CHẠY BUSCO TỰ ĐỘNG NHẬN DIỆN LINEAGE
        # Sẽ chạy qua bacteria_odb10 trước, rồi tự quét sâu xuống nhánh phù hợp
        micromamba run -n busco busco -i "$INPUT_FILE" \
              -o "${SAMPLE}_busco" \
              --out_path "$OUT_DIR" \
              --auto-lineage-prok \
              -m genome \
              -c "$THREADS" \
              --force

        echo "$SAMPLE analysis complete."
    fi
    echo "--------------------------------"
done

# 6. Gom Log kết quả
echo "Final Summary of Short Summaries:"
if ls ${OUT_DIR}/*/short_summary.*.txt 1> /dev/null 2>&1; then
    cat ${OUT_DIR}/*/short_summary.*.txt | grep -E "C:|S:|D:|F:|M:|n:"
else
    echo "No summary files found yet."
fi