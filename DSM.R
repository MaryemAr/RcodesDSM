Packages

install.packages("ithir") 
install.packages("raster") 
install.packages("rgdal") 
install.packages("sp") 
install.packages("rpart") 
install.packages("gstat") 
install.packages("Cubist") 
install.packages("randomForest") 
install.packages("e1071")
install.packages("MASS") 
install.packages("caret")


#Upload packages 

library(ithir) 
library(raster) 
library(rgdal) 
library(sp) 
library(rpart) 
library(gstat) 
library(Cubist) 
library(randomForest) 
library(e1071)
library(MASS)
library(caret)



#set working directory

setwd("H:/2019_Manuscripts/2019_Cubist_RK/After_US_Analysis/Cb_RF_SVM/Analysis/Pttern_sampling/Submission/Computer_&_Geoscience")


#input data (soil observtaions)

cDat <- read.table("Pro_soil_cali.txt", header=T, sep = ",") #calibration dataset 
vDat <- read.table("Pro_soil_vali.txt", header=T, sep = ",") #validation dataset


## 1. Selection of digital data using forward stepwise linear regression
soil.c <- lm(Mg_30 ~K+U+Th+TC ,data = cDat)


#Select the best covariates. Remove the variables with less p value one by one

soil.c.c <- stepAIC(soil.c, direction = "forward", trace = FALSE) 
summary(soil.c.c)



## 2. Developing statistical models

#Fit the LR, Cubist, SVM and RF model one by one with best selcted covariates
# 2.1. For LR model
soil.c.c <- lm(Mg_30 ~K+TC ,data = cDat)  

# 2.2. For Cubist model
grid <- expand.grid(committees = c(1, 10, 50, 100),neighbors = c(0, 1, 5, 9))
set.seed(1)
soil.c.c <- train(x = cDat[, c(  "K", "TC" )],y = cDat$Mg_30, method = "cubist",
                  tuneGrid = grid,trControl = trainControl(method = "cv",number=10))


# 2.3. For support vector machine
tuneResult <- tune(svm, Mg_30 ~K +TC, data = cDat, ranges = list(epsilon = seq(0.1,0.2,0.02), cost = c(5,7,15,20))) 
soil.c.c <- tuneResult$best.model



# 2.4. For random forest
soil.c.c <- randomForest(Mg_30 ~  K+TC, data = cDat,importance = TRUE, ntree = 1000)

## Predictions based on statistical models (using example of cubist model)

pred.v <- predict(soil.c.c, newdata = vDat)

goof1<- goof(observed = vDat$Mg_30,predicted = pred.v) 
print(goof1) 

write.table(goof1, "goof_SVM_Gamma_EM_Mg_30.txt", sep = ",") 
write.table(SVM.pred.v, "Measured_pred_SVM_Gamma_EM_Mg_30.txt", sep = ",")



## 3. Developing hybrid models
# 3.1. Derive regression residual (RR)

cDat$residual <- cDat$Mg_30 - predict(soil.c.c, cDat) 
mean(cDat$residual)

#3.2. Interpolate RR
#Convert data to geodata

coordinates(cDat) <- ~x + y

#Fit variogram to residuals

vgm1 <- variogram(residual ~ K + TC, cDat) 
mod <- vgm(psill = var(cDat$residual), "Sph", range = 400, nugget = 0.5) 
model_1 <- fit.variogram(vgm1, mod) 


#Residual kriging model
gRK <- gstat(NULL, "RKresidual", residual ~ 1, cDat, model = model_1)

#SVM model with residual variogram using ordinary kriging and vDat
coordinates(vDat) <- ~x + y 
RK.preds.V <- as.data.frame(krige(residual ~ 1, cDat, model = model_1, newdata = vDat))

# 3.3. Add RR back
#Sum the two components together
RK.preds.fin2 <- pred.v + RK.preds.V[, 3]

## 4. Predictions based on hybrid models
goof2<- goof(observed = vDat$Mg_30, predicted = RK.preds.fin2) 
print(goof2)

write.table(goof2, "goof_RK_SVM_Gamma_EM_Mg_30.txt", sep = ",") 
write.table(RK.preds.fin2, "Measured_pred_RK_SVM_Gamma_EM_Mg_30.txt", sep = ",")



## 5. Prediction based on hybrid models onto grid (where you only have digital data)
grid <- read.table("Grid.txt", header=T, sep = ",") 
lm.pred.g <- predict(soil.c.c, newdata = grid) 
coordinates(grid) <- ~x + y 
RK.preds.g <- as.data.frame(krige(residual ~ 1, cDat, model = model_1, newdata = grid))
RK.preds.g$var1.pred
RK.preds.g$var1.var


#Sum the two components together
RK.preds.fin <- lm.pred.g + RK.preds.g[, 3] 
error <- RK.preds.g$var1.pred+RK.preds.g$var1.var

write.table(RK.preds.fin, "Grid_Pred_LM_RK_Mg_30.txt", sep = ",") 
write.table(error, "Error_Pred_LM_RK_Mg_30.txt", sep = ",")