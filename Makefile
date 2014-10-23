export SHELLOPTS:=errexit:pipefail
SHELL=/bin/bash  # required to make pipefail work
.SECONDARY:      # do not delete any intermediate files
.SECONDEXPANSION:

LOG = perl -ne 'use POSIX qw(strftime); $$|=1; print strftime("%F %02H:%02M:%S ", localtime), $$ARGV[0], "$@: $$_";'

PATIENTS_TEST = 92
PATIENTS_MATCHED = 108 92 460 545 564 715 737 839 B36 BB16 DL2 GI8 GI13 HV57 HV80 LU3 MA5 N7 S23 SN18 DS10898 VS14645 SE15285 BJ17183 KE17247
PATIENTS_DIA_ONLY = 242 360 365 379 400 506 769 802 833 887 841 903 948 957 961 1060 1066 1089 HW11537 KT14158 TL14516
PATIENTS_REL2 = 108 737
PATIENTS_REL3 = 715

#all: filtered-variants.cosmic.tsv snpeff/mutect_737_rem_rel1.dbsnp.snpeff.dbNSFP.vcf snpeff/mutect_737_rem_rel2.dbsnp.snpeff.dbNSFP.vcf snpeff/mutect_737_rem_dia.dbsnp.snpeff.dbNSFP.vcf snpeff/indels_737_rem_rel1.indel.dbsnp.snpeff.dbNSFP.vcf snpeff/indels_737_rem_rel2.indel.dbsnp.snpeff.dbNSFP.vcf snpeff/indels_737_rem_dia.indel.dbsnp.snpeff.dbNSFP.vcf
all: gene-patient-matrix.tsv filtered-variants.cosmic.tsv filtered-variants.cosmic.merged.tsv coverage-region coverage-genome/allpatients.coverage-genome.pdf exome-coverage/coverage-plots-exome.png coverage-chr21/allpatients.coverage-chr21.pdf picard

#-----------
# DOWNLOAD
#-----------
#wget -r -np -e robots=off --reject *.wig.txt,*_stats.out http://www.biomedical-sequencing.at/projects/BSA_0026_P2RY8_CRLF2_ALL_zahyee0Zooxiphoogo5ooMee3mai8uy8/mutect_b37/ 
#wget -r -np -e robots=off --reject *.wig.txt,*_stats.out http://www.biomedical-sequencing.at/projects/BSA_0026_P2RY8_CRLF2_ALL_zahyee0Zooxiphoogo5ooMee3mai8uy8/indels_b37/
#MuTect,Indelocator results only:
#wget -r -np -e robots=off --accept D_annotated.vcf,R_annotated.vcf,R1_annotated.vcf,R2_annotated.vcf,Diagnosis_annotated.vcf,Relapse_annotated.vcf --limit-rate=1500k http://www.biomedical-sequencing.at/projects/BSA_0026_P2RY8_CRLF2_ALL_zahyee0Zooxiphoogo5ooMee3mai8uy8/
#reprocessed HD samples
#wget -r -np -e robots=off --accept *715*,*460*,*564*,*545* --limit-rate=1500k http://www.biomedical-sequencing.at/projects/BSA_0003_HDBALL_1ca2f4fb9c73e5eb3986819f818f8acb/

~/p2ry8-crlf2/data/mutect_somatic_mutations_hg19/%_calls.vcf: ~/p2ry8-crlf2/data/mutect_somatic_mutations/%_calls.vcf
	cat $< | perl -ne 's/^([\dXY])/chr$$1/; s/^MT/chrM/; print $$_;' > $@.part
	mv $@.part $@

~/p2ry8-crlf2/data/mutect_somatic_indels_hg19/%_indel.vcf: ~/p2ry8-crlf2/data/mutect_somatic_indels/%_indel.vcf
	cat $< | perl -ne 's/^([\dXYM])/chr$$1/; print $$_;' > $@.part
	mv $@.part $@

#-----------
# REMISSION VARIANTS
#-----------
remission-variants.tsv: $(foreach P, $(PATIENTS_MATCHED), remission-variants/$P.remission-variants.tsv) \
					    $(foreach P, $(PATIENTS_DIA_ONLY), remission-variants/$P.remission-variants.tsv) \
					    ~/hdall/results/remission-variants.tsv
	cat $^ | perl -ne 's/chrM/MT/; s/\tchr/\t/; print $$_;' | ~/tools/lh3-sort/sort -k 2,2N -k 3,3n > $@.part
	mv $@.part $@

remission-variants.tsv.gz: remission-variants.tsv
	bgzip -c $^ > $@.part
	mv $@.part $@

remission-variants.tsv.gz.tbi: remission-variants.tsv.gz
	~/tools/tabix-0.2.6/tabix $^ -s 2 -b 3 -e 3

remission-variants/%.remission-variants.tsv: ~/p2ry8-crlf2/data/mutect/%_rem_dia.somatic.vcf ~/p2ry8-crlf2/scripts/create-normal-vcf.pl
	mkdir -p remission-variants 
	cat $< | perl ~/p2ry8-crlf2/scripts/create-normal-vcf.pl --sample-name $* \
		2>&1 1> $@.part | $(LOG)
	mv $@.part $@

#-----------	
# SNPEFF
#-----------	
snpeff/%.dbsnp.vcf: ~/p2ry8-crlf2/data/mutect/%.vcf ~/generic/data/ncbi/common_no_known_medical_impact_20140826.vcf
	PWD=$(pwd)
	(cd ~/tools/snpEff-3.6; java -jar SnpSift.jar annotate \
		-v ~/generic/data/ncbi/common_no_known_medical_impact_20140826.vcf \
		<(cat $< | perl -ne 's/\trs\d+\t/\t.\t/; print $$_;' -) \
		2>&1 1>$(PWD)/$@.part) | $(LOG)
	test -s $@.part
	mv $@.part $@

snpeff/%.dbsnp.snpeff.vcf: snpeff/%.dbsnp.vcf
	PWD=$(pwd)
	(cd ~/tools/snpEff-3.6; java -Xmx4g -jar snpEff.jar -v -lof GRCh37.75 -stats $(PWD)/snpeff/$*.snpeff.summary.html $(PWD)/$< 2>&1 1>$(PWD)/$@.part) | $(LOG)
	mv $@.part $@

snpeff/%.dbsnp.snpeff.dbNSFP.vcf: snpeff/%.dbsnp.snpeff.vcf ~/generic/data/dbNSFP-2.6/dbNSFP2.6_variant.tsv.gz
	PWD=$(pwd)
	(cd ~/tools/snpEff-3.6; java -jar SnpSift.jar dbnsfp \
		-v ~/generic/data/dbNSFP-2.6/dbNSFP2.6_variant.tsv.gz \
		-collapse \
		-f SIFT_pred,SIFT_score,Polyphen2_HVAR_pred,Polyphen2_HVAR_score,SiPhy_29way_logOdds,LRT_pred,LRT_score,MutationTaster_pred,MutationTaster_score,MutationAssessor_pred,MutationAssessor_score,FATHMM_pred,FATHMM_score,RadialSVM_pred,RadialSVM_score,GERP++_RS,1000Gp1_AF,1000Gp1_AFR_AF,1000Gp1_EUR_AF,1000Gp1_AMR_AF,1000Gp1_ASN_AF,ESP6500_AA_AF,ESP6500_EA_AF,Uniprot_acc,Interpro_domain, \
		$(PWD)/$< 2>&1 1>$(PWD)/$@.part) | $(LOG)
	mv $@.part $@

#-------------
# FASTQC
#-------------

.PHONY: fastqc
fastqc: $(foreach P, $(PATIENTS_MATCHED), fastqc/$PC.fastqc.html fastqc/$PD.fastqc.html fastqc/$PR.fastqc.html) \
        $(foreach P, $(PATIENTS_DIA_ONLY), fastqc/$PC.fastqc.html fastqc/$PD.fastqc.html) \
		$(foreach P, $(PATIENTS_REL2), fastqc/$PR2.fastqc.html) \
		$(foreach P, $(PATIENTS_REL3), fastqc/$PR3.fastqc.html)
	
fastqc/%.fastqc.html: ~/p2ry8-crlf2/data/bam/variant_calling_process_sample_%_realigned.bam
	mkdir -p fastqc/$*.part
	~/tools/FastQC/fastqc -o fastqc/$*.part -f bam $^
	mv fastqc/$*.part/* fastqc
	rmdir fastqc/$*.part

#-------------
# REGION COVERAGE
#-------------

GENES_PAR1=PPP2R3B,SHOX,CRLF2,IL3RA,P2RY8,ASMT,DHR3X,ZBED1,CD99
GENES_IKZF1=VWC2,ZPBP,C7orf72,IKZF1,DDC,GRB10,COBL

.PHONY: coverage-region
coverage-region: coverage-region/allpatients.PAR1-X-60001-2699520.pdf \
		  coverage-region/allpatients.IKZF1-7-49578046-51601231.pdf \
		  coverage-region/allpatients.IKZF1_highres-7-50332565-50494236.pdf \
		  coverage-region/allpatients.IKZF2-2-211852462-217849831.pdf \
		  coverage-region/allpatients.IKZF3-17-37789665-38184756.pdf \
		  coverage-region/allpatients.PAX5-9-35800105-38084658.pdf \
		  coverage-region/allpatients.EBF1-5-155175854-161576670.pdf \
		  coverage-region/allpatients.ETV6-12-10309186-13646908.pdf \
		  coverage-region/allpatients.RUNX1-21-34971197-38263248.pdf \
		  coverage-region/allpatients.VPREB1-22-21866719-24317257.pdf \
		  coverage-region/allpatients.ERG-21-38349519-41562975.pdf \
		  coverage-region/allpatients.ERG_highres-21-39739183-40033618.pdf \
		  coverage-region/allpatients.TP53-17-7440139-7721205.pdf \
		  coverage-region/allpatients.RB1-13-46907242-51051394.pdf \
		  coverage-region/allpatients.CDKN2AandB-9-20309360-23721195.pdf \
		  coverage-region/allpatients.CREBBP-16-3067833-4618486.pdf \
		  coverage-region/allpatients.MLL2-12-49295653-49584389.pdf \
		  coverage-region/allpatients.EZH2-7-148002918-149209618.pdf \
		  coverage-region/allpatients.NCOR1-17-15245025-16768909.pdf \
		  coverage-region/allpatients.TUSC3-8-12275019-19439531.pdf \
		  coverage-region/allpatients.WHSC1-4-1615018-2430195.pdf \
		  coverage-region/allpatients.NT5C2-10-104141780-105714035.pdf \
		  coverage-region/allpatients.LEF1-4-108313628-110095704.pdf \
		  coverage-region/allpatients.TCF3-19-1261454-2018719.pdf \
		  coverage-region/allpatients.BLNK-10-97442705-98708695.pdf \
		  coverage-region/allpatients.FOXO3A-6-108206749-109779719.pdf \
		  coverage-region/allpatients.FBXW7-4-151992600-154510682.pdf \
		  coverage-region/allpatients.CREG1-1-167207942-167849758.pdf \
		  coverage-region/allpatients.FLT3_PAN3-13-27955721-29384162.pdf \
		  coverage-region/allpatients.PDGFRB-5-149383560-149648693.pdf \
		  coverage-region/allpatients.STRN3-14-30942316-31995615.pdf \
		  coverage-region/allpatients.RANBP2-2-109007910-109671216.pdf \
		  coverage-region/allpatients.EPOR-19-11393474-11619196.pdf \
		  coverage-region/allpatients.SH2B3-12-111621200-112196224.pdf \
		  coverage-region/allpatients.HIST1H2BD_HIST1H1E-6-26033646-26316674.pdf \
		  coverage-region/allpatients.SPRED1-15-35957458-40803200.pdf \
		  coverage-region/allpatients.ADD3-10-111062840-113085360.pdf \
		  coverage-region/allpatients.ATP10A-15-24452756-27861838.pdf \
		  coverage-region/allpatients.NUP214-9-133609878-134537138.pdf \
		  coverage-region/allpatients.BTG1-12-91300000-93550000.pdf \
		  coverage-region/allpatients.GABRB3-15-25870574-27936343.pdf
		  
coverage-region/%.exon-coverage.tsv: ~/p2ry8-crlf2/data/bam/variant_calling_process_sample_%_realigned.bam /data/christian/generic/data/current/illumina/truseq_exome_targeted_regions.hg19.bed ~/git/hdall/cnv/get-exon-coverage.pl
	~/tools/samtools-0.1.19/samtools depth \
		-Q 1 \
		-b /data/christian/generic/data/current/illumina/truseq_exome_targeted_regions.hg19.bed \
		$< \
	| perl ~/git/hdall/cnv/get-exon-coverage.pl \
		--exon-bed /data/christian/generic/data/current/illumina/truseq_exome_targeted_regions.hg19.bed \
		2>&1 1>$@.part | $(LOG)
	mv $@.part $@

coverage-region/patient%.matched.pdf: coverage-region/$$(word 1, $$(subst ., , %))D.exon-coverage.tsv coverage-region/$$(word 1, $$(subst ., , %))R.exon-coverage.tsv coverage-region/$$(word 1, $$(subst ., , %))C.exon-coverage.tsv ~/p2ry8-crlf2/scripts/cov-plot-region.R
	Rscript ~/p2ry8-crlf2/scripts/cov-plot-region.R \
		--patient $(word 1, $(subst ., , $*)) \
		--sample1 $(word 1,$^) \
		--sample2 $(word 2,$^) \
		--remission $(word 3,$^) \
		--output $@.part \
		--region-name $(word 1, $(subst -, , $(word 2, $(subst ., , $*)))) \
		--display-chrom $(word 2, $(subst -, , $*)) \
		--display-start $(word 3, $(subst -, , $*)) \
		--display-end $(word 4, $(subst -, , $*)) \
		$(if $(GENES_$(word 1, $(subst -, , $(word 2, $(subst ., , $*))))),--display-genes $(GENES_$(word 1, $(subst -, , $(word 2, $(subst ., , $*))))),)
	mv $@.part $@

coverage-region/patient%.diaonly.pdf: coverage-region/$$(word 1, $$(subst ., , %))D.exon-coverage.tsv coverage-region/$$(word 1, $$(subst ., , %))C.exon-coverage.tsv ~/p2ry8-crlf2/scripts/cov-plot-region.R
	Rscript ~/p2ry8-crlf2/scripts/cov-plot-region.R \
		--patient $(word 1, $(subst ., , $*)) \
		--sample1 $(word 1,$^) \
		--remission $(word 2,$^) \
		--output $@.part \
		--region-name $(word 1, $(subst -, , $(word 2, $(subst ., , $*)))) \
		--display-chrom $(word 2, $(subst -, , $*)) \
		--display-start $(word 3, $(subst -, , $*)) \
		--display-end $(word 4, $(subst -, , $*)) \
		$(if $(GENES_$(word 1, $(subst -, , $(word 2, $(subst ., , $*))))),--display-genes $(GENES_$(word 1, $(subst -, , $(word 2, $(subst ., , $*))))),)
	mv $@.part $@

coverage-region/patient%.rel2.pdf: coverage-region/$$(word 1, $$(subst ., , %))R2.exon-coverage.tsv coverage-region/$$(word 1, $$(subst ., , %))C.exon-coverage.tsv ~/p2ry8-crlf2/scripts/cov-plot-region.R
	Rscript ~/p2ry8-crlf2/scripts/cov-plot-region.R \
		--patient $(word 1, $(subst ., , $*)) \
		--sample1 $(word 1,$^) \
		--remission $(word 2,$^) \
		--output $@.part \
		--region-name $(word 1, $(subst -, , $(word 2, $(subst ., , $*)))) \
		--display-chrom $(word 2, $(subst -, , $*)) \
		--display-start $(word 3, $(subst -, , $*)) \
		--display-end $(word 4, $(subst -, , $*)) \
		$(if $(GENES_$(word 1, $(subst -, , $(word 2, $(subst ., , $*))))),--display-genes $(GENES_$(word 1, $(subst -, , $(word 2, $(subst ., , $*))))),)
	mv $@.part $@

coverage-region/allpatients.%.pdf: $(foreach P, $(PATIENTS_MATCHED), coverage-region/patient$P.%.matched.pdf) $(foreach P, $(PATIENTS_DIA_ONLY), coverage-region/patient$P.%.diaonly.pdf) $(foreach P, $(PATIENTS_REL2), coverage-region/patient$P.%.rel2.pdf)
	gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=$@.part $^
	mv $@.part $@
	rm $^

#-------------
# WHOLE-GENOME COVERAGE
#-------------

coverage-genome/allpatients.coverage-genome.pdf: $(foreach P, $(PATIENTS_MATCHED), coverage-genome/$PD.coverage-genome.pdf coverage-genome/$PR.coverage-genome.pdf) \
								    		     $(foreach P, $(PATIENTS_DIA_ONLY), coverage-genome/$PD.coverage-genome.pdf)
	gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=$@.part $^
	mv $@.part $@
	rm $^

coverage-genome/%D.coverage-genome.pdf: coverage-genome/%D.coverage-genome.tsv coverage-genome/%C.coverage-genome.tsv ~/hdall/scripts/cnv/plot-segment-coverage.R
	mkdir -p coverage-genome/circos
	Rscript ~/hdall/scripts/cnv/plot-segment-coverage.R \
		--patient $*D \
		--tumor $(word 1,$^) \
		--normal $(word 2,$^) \
		--circos coverage-genome/circos/$*D.cnv.circos.tsv \
		--output $@.part
	mv $@.part $@

coverage-genome/%R.coverage-genome.pdf: coverage-genome/%R.coverage-genome.tsv coverage-genome/%C.coverage-genome.tsv ~/hdall/scripts/cnv/plot-segment-coverage.R
	mkdir -p coverage-genome/circos
	Rscript ~/hdall/scripts/cnv/plot-segment-coverage.R \
		--patient $*R \
		--tumor $(word 1,$^) \
		--normal $(word 2,$^) \
		--circos coverage-genome/circos/$*R.cnv.circos.tsv \
		--output $@.part
	mv $@.part $@

#coverage-genome/%.coverage-genome.tsv: ~/p2ry8-crlf2/data/bam/variant_calling_process_sample_%_realigned.bam ~/hdall/scripts/cnv/get-segment-coverage.pl
coverage-genome/%.coverage-genome.tsv: ~/p2ry8-crlf2/data/bam/variant_calling_process_sample_%_realigned.bam
	mkdir -p coverage-genome
	~/tools/samtools-0.1.19/samtools depth -Q 1 $< \
		| perl ~/hdall/scripts/cnv/get-segment-coverage.pl --sample $* --bin-size 250000 \
		2>&1 1>$@.part | $(LOG)
	mv $@.part $@

#-------------
# COVERAGE CHROMOSOME 21
#-------------

coverage-chr21/allpatients.coverage-chr21.pdf: $(foreach P, $(PATIENTS_MATCHED) $(PATIENTS_DIA_ONLY), coverage-chr21/$PC.coverage-chr21.pdf)
	gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=$@.part $^
	mv $@.part $@
	rm $^

coverage-chr21/%C.coverage-chr21.pdf: coverage-genome/%C.coverage-genome.tsv coverage-genome/B36C.coverage-genome.tsv ~/hdall/scripts/cnv/plot-segment-coverage-chr21.R
	mkdir -p coverage-chr21 
	Rscript ~/hdall/scripts/cnv/plot-segment-coverage-chr21.R \
		--patient $*C \
		--case $(word 1,$^) \
		--control coverage-genome/B36C.coverage-genome.tsv \
		--output $@.part
	mv $@.part $@

#-------------
# EXOME COVERAGE PLOT (CURVE)
#-------------

exome-coverage/coverage-plots-exome.png: $(foreach P, $(PATIENTS_MATCHED), exome-coverage/$PD.coverage.bedtools.txt exome-coverage/$PR.coverage.bedtools.txt exome-coverage/$PC.coverage.bedtools.txt) \
               					   $(foreach P, $(PATIENTS_DIA_ONLY), exome-coverage/$PD.coverage.bedtools.txt exome-coverage/$PC.coverage.bedtools.txt) \
								   $(foreach P, $(PATIENTS_REL2), exome-coverage/$PR2.coverage.bedtools.txt) \
								   $(foreach P, $(PATIENTS_REL3), exome-coverage/$PR3.coverage.bedtools.txt) \
               					   ~/p2ry8-crlf2/scripts/plot-coverage.R
	Rscript ~/p2ry8-crlf2/scripts/plot-coverage.R

exome-coverage/%.coverage.bedtools.txt: ~/p2ry8-crlf2/data/bam/variant_calling_process_sample_%_realigned.bam ~/generic/data/illumina/nexterarapidcapture_exome_targetedregions.nochr.bed
	~/tools/samtools-0.1.19/samtools view -bq 1 -F 0x400 $< | bedtools coverage -hist -abam - -b $(word 2, $^) | grep ^all > $@.part
	mv $@.part $@

#-------------
# final lists
#-------------
filtered-variants.tsv: $(foreach P, $(PATIENTS_MATCHED), filtered-variants/$P_rem_dia.filtered.tsv filtered-variants/$P_rem_rel.filtered.tsv) \
					   $(foreach P, $(PATIENTS_DIA_ONLY), filtered-variants/$P_rem_dia.filtered.tsv) \
					   $(foreach P, $(PATIENTS_REL2), filtered-variants/$P_rem_rel2.filtered.tsv) \
					   $(foreach P, $(PATIENTS_REL3), filtered-variants/$P_rem_rel3.filtered.tsv) \
					   ~/p2ry8-crlf2/scripts/filter-variants.pl 
	perl ~/p2ry8-crlf2/scripts/filter-variants.pl --header 2>&1 1>$@.part | $(LOG)
	cat filtered-variants/*.filtered.tsv >> $@.part
	mv $@.part $@

filtered-variants.cosmic.tsv: filtered-variants.tsv ~/generic/data/cosmic/v67/CosmicMutantExport_v67_241013.tsv ~/p2ry8-crlf2/scripts/annotate-cosmic.pl
	cat $(word 1,$^) | perl ~/p2ry8-crlf2/scripts/annotate-cosmic.pl \
		--cosmic-mutation-file $(word 2,$^) \
		--only-confirmed \
		2>&1 1>$@.part | $(LOG)
	mv $@.part $@ 
	
filtered-variants.cosmic.merged.tsv: filtered-variants.cosmic.tsv
	Rscript ~/p2ry8-crlf2/scripts/merge-filtered-variants.R 2>&1 | $(LOG)

filtered-variants/%.filtered.tsv: snpeff/%.somatic.dbsnp.snpeff.dbNSFP.vcf ~/hdall/results/curated-recected-variants.tsv remission-variants.tsv.gz.tbi ~/p2ry8-crlf2/scripts/filter-variants.pl
	mkdir -p filtered-variants
	perl ~/p2ry8-crlf2/scripts/filter-variants.pl \
		--sample $* \
		--vcf-in $< \
		--vcf-out filtered-variants/$*.filtered.vcf \
		--rmsk-file ~/generic/data/hg19/hg19.rmsk.txt.gz \
		--simpleRepeat-file ~/generic/data/hg19/hg19.simpleRepeat.txt.gz \
		--segdup-file ~/generic/data/hg19/hg19.genomicSuperDups.txt.gz \
		--blacklist-file ~/generic/data/hg19/hg19.wgEncodeDacMapabilityConsensusExcludable.txt.gz \
		--g1k-accessible ~/generic/data/hg19/paired.end.mapping.1000G..pilot.bed.gz \
		--ucscRetro ~/generic/data/hg19/hg19.ucscRetroAli5.txt.gz \
		--rejected-variants-file ~/hdall/results/curated-recected-variants.tsv \
		--remission-variants-file remission-variants.tsv.gz \
		--evs-file ~/generic/data/evs/ESP6500SI-V2-SSA137.updatedRsIds.chrAll.snps_indels.txt.gz \
		--min-num-rem-to-exclude 3 \
		2>&1 1>$@.part | $(LOG)
	mv $@.part $@

impacted-genes.tsv: filtered-variants.tsv ~/p2ry8-crlf2/scripts/impacted-genes.pl
	cat $< | perl ~/p2ry8-crlf2/scripts/impacted-genes.pl > $@.part
	mv $@.part $@

gene-patient-matrix.tsv: filtered-variants.tsv ~/p2ry8-crlf2/scripts/get-gene-patient-matrix.R
	Rscript ~/p2ry8-crlf2/scripts/get-gene-patient-matrix.R
	mv $@.part $@

#----------------
# FIGURES
#----------------

figures/mutations-per-patient.pdf: filtered-variants.tsv ~/p2ry8-crlf2/scripts/figures/mutations-per-patient.R
	Rscript ~/p2ry8-crlf2/scripts/figures/mutations-per-patient.R
	
#----------------
# PICARD
#----------------

.PHONY: picard
picard: $(foreach P, $(PATIENTS_MATCHED), picard/$PC.picard.insertsize.out picard/$PD.picard.insertsize.out picard/$PR.picard.insertsize.out) \
        $(foreach P, $(PATIENTS_DIA_ONLY), picard/$PC.picard.insertsize.out picard/$PD.picard.insertsize.out) \
		$(foreach P, $(PATIENTS_REL2), picard/$PR2.picard.insertsize.out) \
		$(foreach P, $(PATIENTS_REL3), picard/$PR3.picard.insertsize.out)

picard/%.picard.insertsize.out: ~/p2ry8-crlf2/data/bam/variant_calling_process_sample_%_realigned.bam ~/tools/picard-tools-1.114/CollectInsertSizeMetrics.jar
	mkdir -p picard
	java -jar ~/tools/picard-tools-1.114/CollectInsertSizeMetrics.jar \
		INPUT=$< \
		HISTOGRAM_FILE=picard/$*.picard.insertsize.pdf \
		OUTPUT=$@.part \
		STOP_AFTER=10000000
	mv $@.part $@
	
#---------------
# PINDEL
#---------------

pindel/pindel.cfg: $(foreach P, $(PATIENTS_MATCHED), picard/$PC.picard.insertsize.out picard/$PD.picard.insertsize.out picard/$PR.picard.insertsize.out) \
				   $(foreach P, $(PATIENTS_DIA_ONLY), picard/$PC.picard.insertsize.out picard/$PD.picard.insertsize.out) \
		           $(foreach P, $(PATIENTS_REL2), picard/$PR2.picard.insertsize.out) \
		           $(foreach P, $(PATIENTS_REL3), picard/$PR3.picard.insertsize.out)
	grep -A 1 MEDIAN_INSERT_SIZE $^ | perl -ne 'if (/\/([^\.]+)\.picard.insertsize.out-(\d+)/) { print "/home/STANNANET/christian.frech/p2ry8-crlf2/data/bam/variant_calling_process_sample_$$1_realigned.bam\t$$2\t$$1\n"; }' > $@.part 
	mv $@.part $@ 

.PHONY: pindel
pindel: pindel/allsamples.pindel.tsv

pindel/allsamples_D pindel/allsamples_SI pindel/allsamples_LI pindel/allsamples_TD: pindel/pindel.cfg ~/tools/pindel-0.2.4w/pindel ~/generic/data/broad/hs37d5.fa
	~/tools/pindel-0.2.4w/pindel \
		--fasta ~/generic/data/broad/hs37d5.fa \
		--config-file pindel/pindel.cfg \
		--output-prefix pindel/allsamples \
		--report_long_insertions true \
		--NormalSamples true \
		--minimum_support_for_event 10 \
		--number_of_threads 10 \
		--max_range_index 2 \
		--window_size 1

pindel/allsamples.combined.filtered.vcf: pindel/allsamples_D.vcf pindel/allsamples_SI.vcf pindel/allsamples_LI.vcf pindel/allsamples_TD.vcf ~/p2ry8-crlf2/scripts/filter-pindel.pl
	~/tools/vcftools_0.1.10/bin/vcf-concat \
		<(perl ~/p2ry8-crlf2/scripts/filter-pindel.pl --vcf-in pindel/allsamples_D.vcf) \
		<(perl ~/p2ry8-crlf2/scripts/filter-pindel.pl --vcf-in pindel/allsamples_SI.vcf) \
		<(perl ~/p2ry8-crlf2/scripts/filter-pindel.pl --vcf-in pindel/allsamples_LI.vcf) \
		<(perl ~/p2ry8-crlf2/scripts/filter-pindel.pl --vcf-in pindel/allsamples_TD.vcf) \
		| ~/tools/vcftools_0.1.10/bin/vcf-sort > $@.part
	mv $@.part $@
	
pindel/%.vcf: pindel/%
	~/tools/pindel-0.2.4w/pindel2vcf -p $< -r ~/generic/data/broad/hs37d5.fa -R hs37d5.fa -d 2011-07-01 --both_strands_supported -v $@.part
	mv $@.part $@

pindel/allsamples.combined.filtered.dbsnp.vcf: pindel/allsamples.combined.filtered.vcf ~/generic/data/ncbi/common_no_known_medical_impact_20130930.chr.vcf
	PWD=$(pwd)
	(cd ~/tools/snpEff-3.3h; java -jar SnpSift.jar annotate \
		-v ~/generic/data/ncbi/common_no_known_medical_impact_20130930.chr.vcf \
		<(cat ~/p2ry8-crlf2/results/$< | perl -ne 's/\trs\d+\t/\t.\t/; print $$_;' -) \
		2>&1 1>$(PWD)/$@.part) | $(LOG)
	test -s $@.part
	mv $@.part $@

pindel/allsamples.combined.filtered.dbsnp.snpeff.vcf: pindel/allsamples.combined.filtered.dbsnp.vcf
	PWD=$(pwd)
	(cd ~/tools/snpEff-3.3h; java -Xmx2g -jar snpEff.jar -v -lof hg19 -stats $(PWD)/snpeff/$*.snpeff.summary.html $(PWD)/$< 2>&1 1>$(PWD)/$@.part) | $(LOG)
	mv $@.part $@

pindel/allsamples.combined.filtered.dbsnp.snpeff.dbNSFP.vcf: pindel/allsamples.combined.filtered.dbsnp.snpeff.vcf
	PWD=$(pwd)
	(cd ~/tools/snpEff-3.3h; java -jar SnpSift.jar dbnsfp -v ~/generic/data/dbNSFP-2.1/dbNSFP2.1.txt $(PWD)/$< 2>&1 1>$(PWD)/$@.part) | $(LOG)
	mv $@.part $@

pindel/allsamples.pindel.tsv: pindel/allsamples.combined.filtered.dbsnp.snpeff.dbNSFP.vcf ~/p2ry8-crlf2/scripts/pindel-vcf-to-tsv.pl
	perl ~/p2ry8-crlf2/scripts/pindel-vcf-to-tsv.pl \
		--vcf-in $< \
		--evs-file ~/generic/data/evs/ESP6500SI-V2-SSA137.updatedRsIds.chrAll.snps_indels.txt.gz \
		> $@.part
	mv $@.part $@ 