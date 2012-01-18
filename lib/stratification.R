library("sampling")
library("gam")

nominal_to_binary <- function( orig_data )
{
  data = as.data.frame( orig_data )
  result = NULL
  for (i in 1:ncol(data))
  {
     #print(i)
     if (is.numeric( data[,i] ) )
     {
        if (is.null(result))
          result = data.frame(data[,i])
        else
          result = data.frame(result, data[,i])
        colnames(result)[ncol(result)] <- colnames(data)[i]
     }
     else
     {
        vals = unique(data[,i])
        for (j in 1:length(vals))
        {
           #print(j)
           bins = c()
           for (k in 1:nrow(data))
           {
              if(data[,i][k] == vals[j])
                bins = c(bins,1)
              else
                bins = c(bins,0)
           }
           #print(bins)
           if (is.null(result))
             result = data.frame(bins)
           else
             result = data.frame(result, bins)
           colnames(result)[ncol(result)] <- paste(colnames(data)[i],"is",vals[j])
           if (length(vals)==2) break
        }
     }
  }
  result
}

process_data <- function( data )
{
  if (!is.numeric(data))
    data.num = nominal_to_binary(data)
  else
    data.num = data
  if(any(is.na(data.num)))
  	data.repl = na.gam.replace(data.num)
  else
  	data.repl = data.num
  data.repl
}

stratified_split <- function( data, ratio=0.3 )
{
    data.processed = as.matrix(process_data( data ))
    pik = rep(ratio,times=nrow(data.processed))
    data.strat = cbind(pik,data.processed)
    samplecube(data.strat,pik,order=2,comment=F)
}

stratified_k_fold_split <- function( data, num_folds=10 )
{
  print(paste(num_folds,"-fold-split, data-size",nrow(data)))
  data.processed = as.matrix(process_data( data ))
  folds = rep(0, times=nrow(data))
  for (i in 1:(num_folds-1))
  {
    prop = 1/(num_folds-(i-1))
    print(paste("fold",i,"/",num_folds," prop",prop))
    pik = rep(prop,times=nrow(data))
    for (j in 1:nrow(data))
      if(folds[j]!=0)
        pik[j]=0
    data.strat = cbind(pik,data.processed)
    s<-samplecube(data.strat,pik,order=2,comment=F)
    print(paste("fold size: ",sum(s)))
    for (j in 1:nrow(data))
      if (s[j] == 1)
        folds[j]=i
  }
  for (j in 1:nrow(data))
    if (folds[j] == 0)
      folds[j]=num_folds
  folds
}

plot_split <- function( data, split )
{
  data.processed = process_data( data )
	data.pca <- prcomp(data.processed, scale=TRUE)
  data.2d =as.data.frame(data.pca$x)[1:2]
  plot( NULL,
        xlim = extendrange(data.2d[,1]), ylim = extendrange(data.2d[,2]), 
        xlab = "pc 1", ylab = "pc 2")
  for (j in 0:max(split))
  {
    set = c()
    for (i in 1:nrow(data))
      if (split[i] == j)
        set = c(set,i)
    points(data.2d[set,], pch = 2, col=(j+1))
  }
}

#a<-matrix(rnorm(100, mean=50,  sd=4), ncol=5)
#b<-matrix(rnorm(5000, mean=0, sd=10), ncol=5)
#data<-rbind(a,b)
#c<-matrix(rnorm(50, mean=-50, sd=2), ncol=5)
#data<-rbind(data,c)
#data=iris
#split = stratified_k_fold_split(data, num_folds=3)
#split = stratified_split(data, ratio=0.3)
#plot_split(data,split)




