
function naive(time, period, currentPeriod){
    let final = currentPeriod
    while(final<time){
        final+=period
    }
    return final
}

function constantTime(time, period, currentPeriod){
    if(currentPeriod>time) return currentPeriod
    let low = time - (time-currentPeriod)%period;
    if(low<time) low+=period
    return low
}

function getRandomInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
}

function fuzz(){
    for(let i=0; i<1e8; i++){
        const [time, period, currentPeriod] = [getRandomInt(0, 500), getRandomInt(1, 500), getRandomInt(0,500)]
        if(naive(time, period, currentPeriod) !== constantTime(time, period, currentPeriod)){
            console.log(`Rugged with ${[time, period, currentPeriod]}`)
        }
    }
}

fuzz()