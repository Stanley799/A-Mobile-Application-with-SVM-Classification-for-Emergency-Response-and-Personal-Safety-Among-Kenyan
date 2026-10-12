import json, joblib, numpy as np, pandas as pd, sklearn, imblearn, warnings
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.svm import SVC
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import RepeatedStratifiedKFold, cross_val_predict, StratifiedKFold
from sklearn.metrics import confusion_matrix, accuracy_score
from imblearn.pipeline import Pipeline as ImbPipeline
from imblearn.over_sampling import SMOTENC
warnings.filterwarnings("ignore")
CATEGORICAL=["category","conscious","breathing","severe_bleeding","chest_pain","mobile"]
NUMERIC=["weapon_involved","people_count"]; FEATURES=CATEGORICAL+NUMERIC
LABELS=["Low","Medium","High"]
df=pd.read_csv("data/synthetic_triage_data.csv"); X=df[FEATURES]; y=df["priority"]
cat_idx=list(range(len(CATEGORICAL)))
def build(clf):
    pre=ColumnTransformer([("cat",OneHotEncoder(handle_unknown="ignore"),CATEGORICAL),("num",StandardScaler(),NUMERIC)])
    return ImbPipeline([("smote",SMOTENC(categorical_features=cat_idx,random_state=42,k_neighbors=4)),("prep",pre),("clf",clf)])
models={"LogReg":LogisticRegression(max_iter=2000,C=1.0),
 "SVM-linear C=1":SVC(kernel="linear",C=1,probability=True,random_state=42),
 "SVM-RBF C=1":SVC(kernel="rbf",C=1,probability=True,random_state=42),
 "RandomForest":RandomForestClassifier(n_estimators=200,max_depth=8,random_state=42)}
rep={}
for name,clf in models.items():
    h2l=[];hr=[];acc=[]
    for seed in range(5):  # 5 x 5-fold, pooled per repeat
        p=cross_val_predict(build(clf),X,y,cv=StratifiedKFold(5,shuffle=True,random_state=seed))
        cm=confusion_matrix(y,p,labels=LABELS)
        h2l.append(cm[2,0]); hr.append(cm[2,2]/cm[2].sum()); acc.append(accuracy_score(y,p))
    rep[name]=dict(high_to_low=float(np.mean(h2l)),high_recall=float(np.mean(hr)),acc=float(np.mean(acc)))
    print(f"{name:16s} acc={np.mean(acc):.3f}±{np.std(acc):.3f} highRecall={np.mean(hr):.3f} High->Low errors/run={np.mean(h2l):.1f}")
best=sorted(rep,key=lambda k:(rep[k]["high_to_low"],-rep[k]["high_recall"],-rep[k]["acc"]))[0]
if rep["SVM-linear C=1"]["high_to_low"]<=rep[best]["high_to_low"]+1 and rep["SVM-linear C=1"]["high_recall"]>=rep[best]["high_recall"]-0.05: best="SVM-linear C=1"
print("SELECTED:",best)
final=build(models[best]).fit(X,y); joblib.dump(final,"models/priority_classifier.joblib")
meta={"model":best,"feature_order":FEATURES,"labels":LABELS,"confidence_floor":0.60,
 "allowed_values":{"category":["Medical Emergency","Road Accident","Fire & Rescue","Security Threat","Abduction","Other / General"],
  "conscious":["Yes","No","Unknown"],"breathing":["Yes","No","Unknown"],
  "severe_bleeding":["Yes","No","Unknown","NotAsked"],"chest_pain":["Yes","No","Unknown","NotAsked"],
  "mobile":["Free","Trapped","Unknown","NotAsked"]},
 "sklearn":sklearn.__version__,"imblearn":imblearn.__version__,"data":"synthetic v2 - demo grade, not clinically validated","cv_report":rep}
json.dump(meta,open("models/metadata.json","w"),indent=2)
