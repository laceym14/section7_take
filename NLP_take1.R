# First round of NLP analysis for FWS section 7 take.
# Copyright (c) 2016 Defenders of Wildlife, jmalcom@defenders.org

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/>.
# 

library(cluster)
library(fpc)
library(ggdendro)
library(ggplot2)
library(ggthemes)
library(NLP)
library(openNLP)
library(qdap)
library(quanteda)
library(tm)

##############################################################################
# Get the data ready
load("~/Repos/Defenders/working_papers/_data/take_data.RData")
dim(full)

# What are all of the bull trout consults in this set?
pos <- full[full$BO_species == "Bull Trout (Salvelinus confluentus)" &
            !is.na(full$BO_species), ]
dim(pos)

sub <- full[full$BO_species == "Bull Trout (Salvelinus confluentus)" &
            full$with_take == 1 & !is.na(full$BO_species), ]
dim(sub)
length(unique(sub$take))

##############################################################################
# Start working with take text

# first, how long are these take statements
sub$parts <- sapply(sub$take, FUN = strsplit, split = " ")
sub$n_words <- sapply(sub$parts, FUN = length)
sub$long <- ifelse(sub$n_words > 1, 1, 0)

qplot(sub$n_words, 
      geom = "histogram", 
      xlab = "# words", 
      main = "Length of bull trout take statements") + 
theme_hc()

summary(sub$n_words)

long <- sub[sub$long == 1, ]
take_corp <- corpus(long$take)
docvars(take_corp, "Consult") <- long$activity_code
sum_take_corp <- summary(take_corp)

# look at keywords in context (kwic)
options(width = 200)
num_ctxt <- kwic(take_corp, "\ [0-9]+\ ", window = 5, valuetype = "regex")
acre_ctxt <- kwic(take_corp, "acre", window = 5, valuetype = "regex")
feet_ctxt <- kwic(take_corp, "(feet)|(ft)", window = 5, valuetype = "regex")
take_ctxt <- kwic(take_corp, "take", window = 5, valuetype = "regex")

num_amt_ctxt <- kwic(take_corp, "\ [0-9]+\ ^(acr|ac|ind|mile|mi|feet|ft|lf|linear)",
                     window = 10, 
                     valuetype = "regex")

num_amt_df <- data.frame(doc = num_amt_ctxt$docname,
                         pre = num_amt_ctxt$contextPre,
                         keyword = as.character(num_amt_ctxt$keyword),
                         post = num_amt_ctxt$contextPost,
                         position = as.character(num_amt_ctxt$position))

write.table(num_amt_df,
            file = "~/test_numeric_context_take.tsv",
            sep = "\t",
            quote = FALSE,
            row.names = FALSE)

take_wtok <- tokenize(take_corp, removePunct = TRUE, ngrams = c(1,2))

take_stok <- tokenize(take_corp, what = "sentence")

take_pat1 <- lapply(take_stok, 
                    FUN = grep,
                    pattern = "\ [0-9]+\ (acr|ac|ind|mile|mi|feet|ft|lf|linear)",
                    value = TRUE)
length(take_pat1)
head(take_pat1)

take_pat2 <- lapply(take_pat1, 
                    FUN = grep,
                    pattern = "affect|degrad|harass|harm|injur|kill",
                    value = TRUE)
head(take_pat2, 12)

names(take_pat2) <- paste0(names(take_pat2), "-p")
take_pat3 <- as.data.frame(unlist(take_pat2))
names(take_pat3) <- "take_state"
head(take_pat3)
dim(take_pat3)

# look at POS tags in take_pat3
sent_tok_ann <- Maxent_Sent_Token_Annotator()
word_tok_ann <- Maxent_Word_Token_Annotator()
takep3_ann1 <- annotate(take_pat3$take_state, list(sent_tok_ann, word_tok_ann))

POS_ann <- Maxent_POS_Tag_Annotator()
takep3_POS <- annotate(take_pat3$take_state, POS_ann, takep3_ann1)
POS_words <- subset(takep3_POS, type == "word")
POS_tags <- sapply(POS_words$features, `[[`, "POS")
with_POS <- sprintf("%s/%s", 
                    as.String(take_pat3$take_state)[POS_words], 
                    POS_tags)

takep3_ann2 <- sapply(take_pat3$take_state, 
                      FUN = annotate, 
                      list(sent_tok_ann, word_tok_ann))
ann2_words <- lapply(takep3_ann2, FUN = subset, type == "word")

res <- list()
for (i in 1:length(takep3_ann2)) {
    ares <- annotate(take_pat3$take_state[i], POS_ann, takep3_ann2[[i]])
    ares_w <- data.frame(subset(ares, type == "word"))
    res[[i]] <- ares_w
}

sprintf("%s/%s", as.String(take_pat3$take_state[1])[ann2_words[[1]]], sapply(res[[1]]$features, `[[`, "POS"))

POS_tag_df <- data.frame(row = c(), word = c(), POS = c())
for (i in 1:length(take_pat3$take_state)) {
    parts <- res[[i]]$features
    for (j in 1:length(ann2_words[[i]])) {
        cur_row <- i
        cur_word <- as.String(take_pat3$take_state[i])[ann2_words[[i]][j]]
        cur_POS <- parts[[j]]$POS
        cur_dat <- data.frame(row = cur_row, word = as.character(cur_word), POS = cur_POS)
        POS_tag_df <- rbind(POS_tag_df, cur_dat)
    }
}
head(POS_tag_df)

write.table(POS_tag_df,
            file = "~/POS_test_bulltrout_take_filt.tsv",
            sep = "\t",
            quote = FALSE,
            row.names = FALSE)

# NOTE TO SELF...I left off here, and the next thing to do is label each row/sentence
# as to whether or not it contains a "real" take statement (TRUE) or whether the
# statement is just describing the action (FALSE). Once done, I think I will
# check if there are systematic POS differences between the TRUE and FALSE
# rows, which would make summarizing take authorized possible.


###########################################################################
# Now into the doc-feature matrix
take_dfm <- dfm(take_corp, 
                removePunct = TRUE, 
                stem = TRUE, 
                ngrams = c(1,2),
                ignoredFeatures = stopwords("english"))

options(width = 100)
topfeatures(take_dfm, 20)
word_sums <- colSums(take_dfm)

trim_dfm <- trim(take_dfm, minCount = 4, minDoc = 3)
dim(trim_dfm)
dist_mat <- dist(as.matrix(weight(trim_dfm, "relFreq")))
clust <- hclust(dist_mat)
clust$labels <- long$activity_code

par(mar=c(3,5,5,4))
ggdendrogram(clust)

# Let's take a look at k-means clustering
trim_kmean_3_1 <- kmeans(trim_dfm, centers = 3)
trim_kmean_3_2 <- kmeans(weight(trim_dfm, "relFreq"), centers = 3)
table(trim_kmean_3_1$cluster)
table(trim_kmean_3_2$cluster)

tk31_df <- as.data.frame(trim_kmean_3_1$cluster)
tk31_df <- cbind(tk31_df, summary(take_corp, 215))
names(tk31_df) <- c("cluster", "text", "types", "tokens", "sentences", "consult")
head(tk31_df, 20)

ggplot(data = tk31_df, aes(x = factor(cluster), y = tokens)) +
    geom_boxplot() +
    theme_hc()

tk32_df <- as.data.frame(trim_kmean_3_2$cluster)
tk32_df <- cbind(tk32_df, summary(take_corp, 215))
names(tk32_df) <- c("cluster", "text", "types", "tokens", "sentences", "consult")
head(tk32_df, 20)

ggplot(data = tk32_df, aes(x = factor(cluster), y = tokens)) +
    geom_boxplot() +
    theme_hc()

head(trim_kmean_3$cluster, 20)

trim_kmean_4 <- kmeans(trim_dfm, centers = 4)
table(trim_kmean_4$cluster)
trim_kmean_5 <- kmeans(trim_dfm, centers = 5)
table(trim_kmean_5$cluster)
trim_kmean_6 <- kmeans(trim_dfm, centers = 6)
table(trim_kmean_6$cluster)
trim_kmean_8 <- kmeans(trim_dfm, centers = 8)
table(trim_kmean_8$cluster)

trim_kmean_10 <- kmeans(weight(trim_dfm, "relFreq"), centers = 10)
table(trim_kmean_10$cluster)
tk10_df <- as.data.frame(trim_kmean_10$cluster)
tk10_df <- cbind(tk10_df, summary(take_corp, 215))
names(tk10_df) <- c("cluster", "text", "types", "tokens", "sentences", "consult")
head(tk10_df, 20)
ggplot(data = tk10_df, aes(x = factor(cluster), y = tokens)) +
    geom_boxplot() +
    theme_hc()

trim_kmean_15 <- kmeans(weight(trim_dfm, "relFreq"), centers = 15)
table(trim_kmean_15$cluster)
tk15_df <- as.data.frame(trim_kmean_15$cluster)
tk15_df <- cbind(tk15_df, summary(take_corp, 215))
names(tk15_df) <- c("cluster", "text", "types", "tokens", "sentences", "consult")
head(tk15_df, 20)
ggplot(data = tk15_df, aes(x = factor(cluster), y = tokens)) +
    geom_boxplot() +
    theme_hc()

trim_dfm2 <- trim(take_dfm, minCount = 5, minDoc = 5)
dim(trim_dfm2)

trim_kmean_15 <- kmeans(weight(trim_dfm2, "relFreq"), centers = 15)
table(trim_kmean_15$cluster)
tk15_df <- as.data.frame(trim_kmean_15$cluster)
tk15_df <- cbind(tk15_df, summary(take_corp, 215))
names(tk15_df) <- c("cluster", "text", "types", "tokens", "sentences", "consult")
head(tk15_df, 20)
ggplot(data = tk15_df, aes(x = factor(cluster), y = tokens)) +
    geom_boxplot() +
    theme_hc()

cl15 <- tk15_df[tk15_df$cluster == 15, ]$consult
cl15_dat <- long[long$activity_code %in% cl15, ]
cl15_corp <- corpus(cl15_dat$take)
cl15_dfm <- dfm(cl15_corp, 
                removePunct = TRUE, 
                stem = TRUE, 
                ngrams = c(1,2),
                ignoredFeatures = stopwords("english"))

topfeatures(take_dfm, 20)
cl15_trim <- trim(cl15_dfm, minCount = 4, minDoc = 3)

trim_kmean_15foc <- kmeans(weight(trim_dfm2, "relFreq"), centers = 6)
table(trim_kmean_15foc$cluster)
tk15_df <- as.data.frame(trim_kmean_15foc$cluster)
tk15_df <- cbind(tk15_df, summary(take_corp, 215))
names(tk15_df) <- c("cluster", "text", "types", "tokens", "sentences", "consult")
head(tk15_df, 20)
ggplot(data = tk15_df, aes(x = factor(cluster), y = tokens)) +
    geom_boxplot() +
    theme_hc()


plotcluster(trim_dfm, trim_kmean_3_2$cluster)

similarity(trim_dfm, 
           c("acr", "feet", "take", "individu"), 
           method = "correlation", 
           margin = "features", 
           n = 20)

